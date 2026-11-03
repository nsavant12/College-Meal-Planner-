"""Convert a selected grocery checkpoint to FP16 Core ML, validating real val pixels.
Run on macOS after training, with coremltools==8.3.0 installed.
"""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
import torch
from torch import nn
from train_classifier import make_model

class ExportModel(nn.Module):
    def __init__(self,model):
        super().__init__();self.model=model
        self.register_buffer('mean',torch.tensor([.485,.456,.406]).view(1,3,1,1))
        self.register_buffer('std',torch.tensor([.229,.224,.225]).view(1,3,1,1))
    def forward(self,image):return self.model((image-self.mean)/self.std).softmax(-1)

def main():
    import coremltools as ct
    p=argparse.ArgumentParser()
    p.add_argument('--checkpoint',type=Path,required=True)
    p.add_argument('--data',type=Path,default=Path('vision-data/grocery'))
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    saved=torch.load(args.checkpoint,map_location='cpu',weights_only=True)
    model=make_model(saved['arch'],len(saved['labels']),False);model.load_state_dict(saved['state']);model.eval()
    wrapper=ExportModel(model).eval();size=saved['size']
    labels=[saved['labels'][str(i)] for i in range(len(saved['labels']))]
    # Explicit equivalents only; preserve plant/dairy products and juice distinctions.
    aliases={'aubergine':'eggplant','carrots':'carrot','yoghurt':'yogurt','pepper':'bell pepper'}
    labels=[aliases.get(n,n) for n in labels]
    with torch.inference_mode(): traced=torch.jit.trace(wrapper,torch.rand(1,3,size,size))
    converted=ct.convert(traced,inputs=[ct.ImageType(name='image',shape=(1,3,size,size),scale=1/255)],
                         classifier_config=ct.ClassifierConfig(labels),minimum_deployment_target=ct.target.iOS17,
                         compute_precision=ct.precision.FLOAT16)
    converted.user_defined_metadata['preprocessing']='RGB scaleFit black padding; embedded ImageNet normalization'
    converted.user_defined_metadata['dataset_revision']=saved['dataset_revision']
    audit=json.loads((args.data/'audit.json').read_text())
    if audit['revision']!=saved['dataset_revision']:raise ValueError('Dataset revision mismatch')
    probability_name=converted.get_spec().description.predictedProbabilitiesName
    max_error=0
    validation=audit['splits']['val']
    if not validation:raise ValueError('No validation images for conversion parity')
    for row in validation[::max(1,len(validation)//16)][:16]:
        with Image.open(args.data/row['file']) as source:
            pixels=ImageOps.pad(ImageOps.exif_transpose(source).convert('RGB'),(size,size),method=Image.Resampling.BILINEAR,color=(0,0,0))
        tensor=torch.from_numpy(np.array(pixels).copy()).permute(2,0,1).float().unsqueeze(0)/255
        with torch.inference_mode():expected=wrapper(tensor)[0].numpy()
        actual_dict=converted.predict({'image':pixels})[probability_name]
        actual=np.array([actual_dict[n] for n in labels])
        np.testing.assert_allclose(actual,expected,atol=.02,rtol=.05)
        max_error=max(max_error,float(np.max(np.abs(actual-expected))))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    converted.save(str(args.output))
    print(f'Saved {args.output}; val pixel parity max error {max_error:.6f}. Still requires native app/device evaluation.')

if __name__=='__main__':main()
