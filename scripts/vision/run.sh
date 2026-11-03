#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export TORCH_HOME="$PWD/vision-data/weights"
export HF_HOME="$PWD/vision-data/huggingface"
export MPLCONFIGDIR="$PWD/vision-data/matplotlib"
mode="${1:-help}"
case "$mode" in
  setup)
    if [[ ! -x .vision-env/bin/python ]]; then
      uv venv --python 3.12 .vision-env
    fi
    uv pip install --python .vision-env/bin/python -r scripts/vision/requirements.txt
    ;;
  grocery)
    .vision-env/bin/python scripts/vision/grocery.py
    .vision-env/bin/python scripts/vision/train_classifier.py train --output vision-runs/grocery-efficientnet --device auto
    .vision-env/bin/python scripts/vision/train_classifier.py test --output vision-runs/grocery-efficientnet --device auto
    ;;
  detectors)
    .vision-env/bin/python scripts/vision/download.py
    for model in ssdlite rf-nano rf-small; do
      .vision-env/bin/python scripts/vision/benchmark.py \
        --annotations vision-data/coco/annotations/instances_val2017.json \
        --images vision-data/coco/val2017 --model "$model" \
        --output "vision-runs/coco-$model" --device cpu
    done
    ;;
  export)
    uv pip install --python .vision-env/bin/python coremltools==8.3.0
    .vision-env/bin/python scripts/vision/export_classifier.py \
      --checkpoint vision-runs/grocery-efficientnet/best.pt \
      --output vision-runs/grocery-efficientnet/IngredientClassifier.mlpackage
    ;;
  *) printf '%s\n' 'Usage: bash scripts/vision/run.sh {setup|grocery|detectors|export}';;
esac
