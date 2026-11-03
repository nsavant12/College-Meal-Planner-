#!/usr/bin/env python3
"""Export fixed-shape, FP16 SSDLite; deliberately leave NMS to the app.
Python 3.9–3.12; torch 2.7.0, torchvision 0.22.0, coremltools 8.3.0.
Weights are downloaded by torchvision; inspect upstream terms before distribution.
"""
import argparse
from pathlib import Path
import numpy as np
import torch
from torch import nn
import torchvision
from torchvision.models.detection import ssdlite320_mobilenet_v3_large, SSDLite320_MobileNet_V3_Large_Weights
import coremltools as ct

LABELS = ["banana", "apple", "orange", "broccoli", "carrot"]

class MobileFoodDetector(nn.Module):
    def __init__(self, detector, categories):
        super().__init__()
        self.detector = detector
        self.indices = [categories.index(name) for name in LABELS]
        # Fixed anchors and image geometry; avoid exporting Python postprocessing.
        from torchvision.models.detection.image_list import ImageList
        dummy = torch.zeros(1, 3, 320, 320)
        with torch.no_grad():
            features = list(detector.backbone(dummy).values())
            anchors = detector.anchor_generator(ImageList(dummy, [(320, 320)]), features)[0]
        self.register_buffer("anchors", anchors)
        self.register_buffer("mean", torch.tensor(detector.transform.image_mean).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(detector.transform.image_std).view(1, 3, 1, 1))

    def forward(self, image):
        features = list(self.detector.backbone((image - self.mean) / self.std).values())
        head = self.detector.head(features)
        boxes = self.detector.box_coder.decode_single(head["bbox_regression"][0], self.anchors)
        probabilities = head["cls_logits"][0].softmax(-1)
        # Preserve competition with background/non-food classes.
        scores = probabilities[:, self.indices]
        scores = scores * (scores >= probabilities.max(-1, keepdim=True).values).to(scores.dtype)
        return (boxes / 320.0).clamp(0, 1), scores

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    torch.manual_seed(0)
    torch.set_num_threads(1)
    weights = SSDLite320_MobileNet_V3_Large_Weights.COCO_V1
    detector = ssdlite320_mobilenet_v3_large(weights=weights).eval()
    wrapper = MobileFoodDetector(detector, weights.meta["categories"]).eval()
    example = torch.rand(1, 3, 320, 320)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)
        # Test trace generalization on a second input, not just the trace sample.
        second = torch.rand_like(example)
        for actual, expected in zip(traced(second), wrapper(second)):
            torch.testing.assert_close(actual, expected)
    model = ct.convert(traced, inputs=[ct.ImageType(name="image", shape=example.shape, scale=1/255.0)],
                       outputs=[ct.TensorType(name="boxes"), ct.TensorType(name="scores")],
                       minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16)
    model.user_defined_metadata["ingredient_detector_contract"] = "ssdlite320-coco-food-v1"
    model.user_defined_metadata["labels"] = ",".join(LABELS)
    model.user_defined_metadata["weights"] = weights.url
    model.user_defined_metadata["torchvision"] = torchvision.__version__
    model.short_description = "SSDLite320 MobileNetV3: visible COCO food instances; not mass or safety."
    args.output.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(args.output))
    # Conversion parity on real RGB pixels; fail instead of shipping a bad export.
    from PIL import Image
    rng = np.random.default_rng(0)
    pixels = rng.integers(0, 256, (320, 320, 3), dtype=np.uint8)
    with torch.no_grad():
        expected = wrapper(torch.from_numpy(pixels.copy()).permute(2, 0, 1).float().unsqueeze(0) / 255)
    actual = model.predict({"image": Image.fromarray(pixels)})
    for name, reference in zip(["boxes", "scores"], expected):
        np.testing.assert_allclose(actual[name], reference.numpy(), atol=0.025, rtol=0.05)
    print(f"Saved {args.output}; trace and FP16 conversion parity passed")

if __name__ == "__main__":
    main()
