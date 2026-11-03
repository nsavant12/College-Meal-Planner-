"""Review completed runs without rerunning inference or overwriting acceptance results.
Alternative precision floors are post-result exploratory analyses; not independent tests.
"""
import argparse
import json
from pathlib import Path
from benchmark import FOOD, digest, partition, select_threshold, summarize


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runs', type=Path, default=Path('vision-runs'))
    parser.add_argument('--annotations', type=Path, default=Path('vision-data/coco/annotations/instances_val2017.json'))
    parser.add_argument('--output', type=Path, default=Path('docs/vision-benchmark-review.json'))
    args = parser.parse_args()
    data = json.loads(args.annotations.read_text())
    evaluation = [im for im in data['images'] if partition(im['id']) == 'evaluation']
    review = {'scope': 'Five COCO ingredient categories; alternate floors are exploratory after original results.',
              'detectors': {}, 'source_hashes': {str(args.annotations): digest(args.annotations)}}
    for model in ['ssdlite', 'rf-nano', 'rf-small']:
        root = args.runs / ('coco-' + model)
        summary = json.loads((root/'summary.json').read_text())
        run = json.loads((root/'run.json').read_text())
        if run['annotations_sha256'] != digest(args.annotations):
            raise ValueError('Annotations changed since inference')
        rows = [json.loads(line) for line in (root/'predictions.jsonl').read_text().splitlines()]
        records = {r['image_id']: r for r in rows}
        if len(records) != len(rows) or set(records) != {im['id'] for im in data['images']}:
            raise ValueError('Duplicate or incomplete predictions')
        review['source_hashes'][str(root/'summary.json')] = digest(root/'summary.json')
        alternatives = []
        for floor in [.90, .85, .80]:
            threshold = select_threshold(summary['calibration_sweep'], floor)
            metrics = summarize(evaluation, data['annotations'], records, threshold, FOOD) if threshold is not None else None
            alternatives.append({'calibration_precision_floor': floor, 'threshold': threshold,
                                 'evaluation': metrics})
        review['detectors'][model] = {'original_threshold': summary['threshold'],
            'original_target_met': summary['target_met_on_this_scope'],
            'host_latency_ms': summary['host_latency_ms'], 'coco_bbox': summary['coco_bbox'],
            'operating_points': alternatives}
    root = args.runs/'grocery-efficientnet'
    classifier = json.loads((root/'test-summary.json').read_text())
    review['source_hashes'][str(root/'test-summary.json')] = digest(root/'test-summary.json')
    review['classifier'] = {k: v for k, v in classifier.items() if k != 'predictions'}
    review['classifier']['weakest_classes'] = sorted(classifier['per_class_recall'].items(), key=lambda pair: pair[1])[:8]
    native = root/'native-val-summary.json'
    if native.exists():
        native_summary = json.loads(native.read_text())
        review['native_validation'] = {k: v for k, v in native_summary.items() if k != 'predictions'}
        review['source_hashes'][str(native)] = digest(native)
    regression = root/'native-app-regression.json'
    if regression.exists():
        review['native_regression'] = json.loads(regression.read_text())
        review['source_hashes'][str(regression)] = digest(regression)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(review, indent=2, allow_nan=False)+'\n')
    for model, result in review['detectors'].items():
        for point in result['operating_points']:
            metrics = point['evaluation']
            print(model, point['threshold'], metrics['micro'] if metrics else 'No qualifying threshold')
    print('Saved', args.output)

if __name__ == '__main__':
    main()
