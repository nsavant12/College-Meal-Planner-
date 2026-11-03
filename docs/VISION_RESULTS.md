# Vision model results

The default app uses Apple's on-device classifier. The experimental EfficientNetV2-S classifier and RF-DETR detectors are not bundled. Results below were measured on a Mac; they are not iPhone latency or full-pipeline accuracy claims.

## Grocery classification

EfficientNetV2-S reached **96.34% top-1/micro recall**, **94.35% macro recall**, and **99.36% top-3 recall** on the 2,485-image Grocery Store Dataset test split. Each image has one foreground label, so these results do not measure mixed-food precision or counting. The exact-byte audit found no cross-split duplicates; near duplicates and pretraining overlap remain possible.

Recall varied by class: mango 61.3%, satsumas 66.2%, cucumber 70.4%, and ginger 73.3%. The audited dataset revision has 2,640 training, 296 validation, and 2,485 test images across 43 coarse classes. Source: [Grocery Store Dataset](https://github.com/marcusklasson/GroceryStoreDataset).

The FP16 Core ML export is about 40.6 MB. On 296 validation images, native Vision achieved 96.62% top-1 recall. After the app's current vocabulary and confidence filter, recall was 59.12% across all images and 95.11% on the 184 images with supported labels. The export's sampled validation probabilities passed `atol=0.02, rtol=0.05` parity checks; the largest absolute difference was 0.028546.

The actual app recognizer failed three of six mixed-food/non-food regression cases with the new classifier: it added avocado to a fruit plate, missed bell pepper in a vegetable display, and labeled a hammer as carrot. The classifier needs broader vocabulary and non-food/mixed-scene handling before deployment.

## Detection and counting

The COCO experiment processed 5,000 images. The evaluation partition has 4,010 images, including 248 containing at least one of five supported categories: banana, apple, orange, broccoli, and carrot. Thresholds were chosen on a separate calibration partition to meet a 90% precision floor.

| Model | Threshold | Precision | Micro recall | Macro recall | Mac CPU p50 / p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| SSDLite | 0.75 | 95.6% | 26.2% | 25.5% | 69.3 / 73.0 ms |
| RF-DETR Nano | 0.55 | 94.0% | 56.9% | 56.6% | 48.4 / 51.9 ms |
| RF-DETR Small | 0.50 | 92.6% | 64.2% | 63.8% | 84.2 / 86.3 ms |

An exploratory RF-DETR Small threshold of **0.35**, selected using an 85% calibration precision floor, achieved **77.7% micro recall**, **77.5% macro recall**, and **86.6% precision** on evaluation. This meets the recall target for those five categories, but the alternative was examined after the original results and needs independent kitchen-scene validation. COCO does not measure the full pantry vocabulary.

At 0.35, RF-DETR Small got **36.4% of positive counts exactly right**, with a positive-count mean absolute error of 1.93. Crowd-labeled pairs were excluded. Counting needs per-instance kitchen annotations and further model work.

## Reproduce

From the repository root, set up the isolated environment and run the larger experiments:

```sh
bash scripts/vision/run.sh setup
bash scripts/vision/run.sh grocery
bash scripts/vision/run.sh detectors
```

These jobs download several GB and can take hours. Detector predictions are cached and resume with the same configuration. Training saves the best validation checkpoint but does not resume optimizer state. `vision-data/`, `vision-runs/`, and `.vision-env/` are local and ignored by Git. The detector comparison uses TorchVision reference postprocessing for SSDLite, not the combined Swift pipeline.

Review completed runs and export the selected classifier:

```sh
.vision-env/bin/python scripts/vision/review_runs.py
bash scripts/vision/run.sh export
```

The export command checks sampled validation pixels and writes `vision-runs/grocery-efficientnet/IngredientClassifier.mlpackage`; it does not add the model to the app. Results and source hashes are recorded in [vision-benchmark-review.json](vision-benchmark-review.json). The original predictions and checkpoints remain in the local run directories.

To evaluate native whole-image classification on the validation split:

```sh
.vision-env/bin/python scripts/vision/prepare_native_manifest.py \
  --split val --output vision-runs/grocery-efficientnet/native-val-manifest.json
mkdir -p /private/tmp/GroceryClassifier.bundle
xcrun coremlcompiler compile \
  vision-runs/grocery-efficientnet/IngredientClassifier.mlpackage /private/tmp/GroceryClassifier.bundle
xcrun swiftc -parse-as-library -swift-version 5 \
  "Recipe Maker/Recipe Maker/Core/Ingredient.swift" \
  scripts/vision/NativeClassifierEvaluation.swift -o /private/tmp/native-classifier-evaluation
/private/tmp/native-classifier-evaluation \
  /private/tmp/GroceryClassifier.bundle/IngredientClassifier.mlmodelc \
  vision-runs/grocery-efficientnet/native-val-manifest.json \
  vision-runs/grocery-efficientnet/native-val-summary.json
```

Use `--split test` with separate output paths to evaluate the held-out test split. Native validation measures one classification per image, not regional scanning or incidental-food false positives.

## Next work

- Expand canonical ingredient labels without merging juice with fruit or plant-based products with dairy.
- Improve rejection of non-food images and mixed-scene errors; validate on independent kitchen photos.
- Improve counting using instance-level annotations, then evaluate the 0.35 detector operating point on a source-disjoint kitchen set.
- Measure model load, latency, memory, and repeated scans on supported iPhones before bundling weights.

The model and conversion code use TorchVision and Core ML. Review the pretrained weights' dataset-derived terms before distributing model artifacts. MVTec D2S is a potential instance-annotated supermarket benchmark, but its [license is noncommercial](https://www.mvtec.com/research-teaching/datasets/mvtec-d2s) and its test annotations are withheld.
