"""Resumable COCO-format model comparison. All images, including negatives, are used.
Inference caches raw ranked detections once; threshold selection only uses calibration.
Stock models support five app ingredients; this is explicitly NOT broad-food recall.
"""
import argparse
from collections import Counter, defaultdict
import contextlib
import hashlib
import importlib.metadata
import io
import json
import math
from pathlib import Path
import platform
import time

FOOD = {52:'banana', 53:'apple', 55:'orange', 56:'broccoli', 57:'carrot'}
THRESHOLDS = [i/100 for i in range(5, 81, 5)]


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        while block := f.read(1024*1024):
            h.update(block)
    return h.hexdigest()


def partition(image_id):
    # Stable partition of COCO val, not a new independent test dataset.
    return 'calibration' if int(hashlib.sha256(f'food-v1:{image_id}'.encode()).hexdigest()[:8], 16) % 5 == 0 else 'evaluation'


def ratio(a,b):
    return a/b if b else None


def summarize(images, annotations, records, threshold, categories):
    per = {c:Counter() for c in categories}
    gt = defaultdict(list)
    for a in annotations:
        gt[a['image_id']].append(a)
    exact = negative = false_negative_scene = 0
    errors, positives = [], []
    for image in images:
        image_id = image['id']
        # Presence may use crowds; individual count metrics exclude crowded classes.
        truth = Counter(a['category_id'] for a in gt[image_id] if a['category_id'] in categories)
        crowded = {a['category_id'] for a in gt[image_id] if a.get('iscrowd',0)}
        pred = Counter(d['category_id'] for d in records[image_id]['detections'] if d['score'] >= threshold and d['category_id'] in categories)
        exact += set(truth) == set(pred)
        negative += not truth
        false_negative_scene += not truth and bool(pred)
        for c in categories:
            per[c]['tp' if c in truth and c in pred else 'fp' if c in pred else 'fn' if c in truth else 'tn'] += 1
            if c not in crowded:
                error = abs(pred[c]-truth[c])
                errors.append(error)
                if truth[c]:
                    positives.append(error)
    totals = sum(per.values(), Counter())
    def m(v):
        return dict(v, precision=ratio(v['tp'],v['tp']+v['fp']), recall=ratio(v['tp'],v['tp']+v['fn']))
    recalls = [m(v)['recall'] for v in per.values() if v['tp']+v['fn']]
    return dict(images=len(images), micro=m(totals), macro_recall=ratio(sum(recalls),len(recalls)),
                per_class={categories[c]:m(v) for c,v in per.items()}, exact_set_accuracy=ratio(exact,len(images)),
                negative_images=negative, negative_false_positive_rate=ratio(false_negative_scene,negative),
                count_mae=ratio(sum(errors),len(errors)), positive_count_pairs=len(positives),
                positive_count_mae=ratio(sum(positives),len(positives)), positive_count_exact=ratio(sum(e==0 for e in positives),len(positives)))


def select_threshold(sweep, precision_floor):
    eligible = [(t,m) for t,m in sweep if m['micro']['precision'] is not None and m['micro']['precision'] >= precision_floor and m['micro']['recall'] is not None]
    return max(eligible, key=lambda tm:(tm[1]['micro']['recall'],tm[1]['micro']['precision'],tm[0]))[0] if eligible else None


def make_predictor(name, device):
    import torch
    if name == 'ssdlite':
        from torchvision.models.detection import ssdlite320_mobilenet_v3_large, SSDLite320_MobileNet_V3_Large_Weights
        from torchvision.transforms.functional import to_tensor
        model = ssdlite320_mobilenet_v3_large(weights=SSDLite320_MobileNet_V3_Large_Weights.COCO_V1,
                                            score_thresh=.001, detections_per_img=300).eval().to(device)
        def predict(image):
            with torch.inference_mode():
                r = model([to_tensor(image).to(device)])[0]
            return r['boxes'].cpu().tolist(), r['scores'].cpu().tolist(), r['labels'].cpu().tolist()
    else:
        from rfdetr import RFDETRNano, RFDETRSmall, RFDETRMedium
        cls = {'rf-nano':RFDETRNano,'rf-small':RFDETRSmall,'rf-medium':RFDETRMedium}[name]
        model = cls(device=device)
        def predict(image):
            r = model.predict(image, threshold=.001)
            return r.xyxy.tolist(), r.confidence.tolist(), r.class_id.tolist()
    if name == 'ssdlite':
        weight_path = Path(torch.hub.get_dir())/'checkpoints'/'ssdlite320_mobilenet_v3_large_coco-a79551df.pth'
    else:
        weight_path = Path(model.model_config.pretrain_weights)
    return predict, dict(path=str(weight_path.resolve()), sha256=digest(weight_path))


def infer(args, data, images):
    from PIL import Image
    import torch
    device = args.device
    if device == 'auto':
        device = 'cuda' if torch.cuda.is_available() else 'mps' if torch.backends.mps.is_available() else 'cpu'
    config = dict(runner_sha256=digest(Path(__file__)), model=args.model, device=device, annotations_sha256=digest(args.annotations),
                  image_root=str(args.images.resolve()), image_ids=[i['id'] for i in images],
                  packages={n:importlib.metadata.version(n) for n in ['torch','torchvision','rfdetr','pycocotools']},
                  platform=platform.platform(), raw_threshold=.001)
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = args.output/'run.json'
    if manifest.exists() and json.loads(manifest.read_text()) != config:
        raise ValueError('Run configuration changed; choose a new output directory')
    manifest.write_text(json.dumps(config,indent=2)+'\n')
    cache = args.output/'predictions.jsonl'
    records = {}
    if cache.exists():
        # Never silently accept a truncated last line or duplicate image.
        for line in cache.read_text().splitlines():
            row = json.loads(line)
            if row['image_id'] in records:
                raise ValueError('Duplicate cached image')
            records[row['image_id']] = row
    if any(i not in {im['id'] for im in images} for i in records):
        raise ValueError('Cache includes unknown images')
    by_id = {im['id']:im for im in images}
    for image_id, row in records.items():
        if digest(args.images/by_id[image_id]['file_name']) != row.get('image_sha256'):
            raise ValueError('Cached source image changed or lacks a hash; use a fresh run directory')
    if len(records) == len(images):
        weights=json.loads((args.output/'weights.json').read_text())
        if digest(Path(weights['path'])) != weights['sha256']:
            raise ValueError('Cached model weights changed')
        return records
    started = time.perf_counter()
    predictor, weights = make_predictor(args.model, device)
    weight_manifest=args.output/'weights.json'
    if weight_manifest.exists() and json.loads(weight_manifest.read_text()) != weights:
        raise ValueError('Model weights changed; use a fresh output directory')
    weight_manifest.write_text(json.dumps(weights,indent=2)+'\n')
    print(f'Model load: {time.perf_counter()-started:.1f}s; device={device}',flush=True)
    with cache.open('a') as out:
        for index, im in enumerate(images):
            if im['id'] in records:
                continue
            with Image.open(args.images/im['file_name']) as source:
                image = source.convert('RGB')
            # COCO boxes use stored pixels, not EXIF-transposed coordinates.
            if image.size != (im['width'],im['height']):
                raise ValueError('Image geometry disagrees with annotations')
            started = time.perf_counter()
            boxes,scores,labels = predictor(image)
            detections = []
            for b,s,c in zip(boxes,scores,labels):
                if not math.isfinite(s) or not 0 <= s <= 1 or not all(math.isfinite(x) for x in b):
                    raise ValueError('Invalid model output')
                if c not in FOOD:
                    continue
                x1,y1,x2,y2 = max(0,b[0]),max(0,b[1]),min(im['width'],b[2]),min(im['height'],b[3])
                if x2 > x1 and y2 > y1:
                    detections.append(dict(image_id=im['id'],category_id=c,score=s,bbox=[x1,y1,x2-x1,y2-y1]))
            row = dict(image_id=im['id'],image_sha256=digest(args.images/im['file_name']),milliseconds=(time.perf_counter()-started)*1000,detections=detections)
            out.write(json.dumps(row,allow_nan=False)+'\n'); out.flush()
            records[im['id']] = row
            if (index+1)%25 == 0 or index == len(images)-1:
                print(f'{index+1}/{len(images)} images; last inference {row["milliseconds"]:.0f}ms',flush=True)
    return records


def coco_metrics(data, images, records):
    from pycocotools.coco import COCO
    from pycocotools.cocoeval import COCOeval
    import numpy as np
    coco = COCO()
    coco.dataset = dict(data, info=data.get('info',{}))
    stream = io.StringIO()
    with contextlib.redirect_stdout(stream):
        coco.createIndex()
        predictions = [d for im in images for d in records[im['id']]['detections']]
        if predictions:
            dt = coco.loadRes(predictions)
        else:
            dt = COCO(); dt.dataset = dict(images=data['images'],categories=data['categories'],annotations=[]); dt.createIndex()
        evaluator = COCOeval(coco, dt, 'bbox')
        evaluator.params.imgIds = [im['id'] for im in images]
        evaluator.params.catIds = sorted(FOOD)
        evaluator.evaluate(); evaluator.accumulate(); evaluator.summarize()
    stats = evaluator.stats.tolist()
    return dict(zip(['AP','AP50','AP75','AP_small','AP_medium','AP_large','AR1','AR10','AR100','AR_small','AR_medium','AR_large'],[v if v>=0 else None for v in stats])),stream.getvalue()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--annotations',type=Path,required=True)
    p.add_argument('--images',type=Path,required=True)
    p.add_argument('--model',choices=['ssdlite','rf-nano','rf-small','rf-medium'],required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--device',choices=['auto','cpu','mps','cuda'],default='cpu')
    p.add_argument('--limit',type=int,default=0,help='Smoke only; never accepted as a complete benchmark')
    p.add_argument('--precision-floor',type=float,default=.90)
    args = p.parse_args()
    if args.limit < 0 or not 0 < args.precision_floor <= 1:
        p.error('Invalid limit/precision floor')
    data = json.loads(args.annotations.read_text())
    if {c['id']:c['name'] for c in data['categories'] if c['id'] in FOOD} != FOOD:
        raise ValueError('Requires COCO category IDs; do not silently reuse this mapping on another dataset')
    images = sorted(data['images'],key=lambda im:im['id'])
    if len({im['id'] for im in images}) != len(images):
        raise ValueError('Duplicate image IDs')
    if args.limit:
        images=images[:args.limit]
    if not images:
        raise ValueError('Empty corpus')
    records = infer(args,data,images)
    calibration = [im for im in images if partition(im['id'])=='calibration']
    evaluation = [im for im in images if partition(im['id'])=='evaluation']
    sweep = [(t,summarize(calibration,data['annotations'],records,t,FOOD)) for t in THRESHOLDS]
    threshold = select_threshold(sweep,args.precision_floor)
    report = dict(model=args.model,complete_coco_val=len(images)==5000 and not args.limit,
                  scope='Five COCO ingredient categories, not the complete pantry vocabulary',
                  target_recall=.75,stretch_recall=.80,precision_floor=args.precision_floor,
                  threshold=threshold,calibration_sweep=sweep,
                  evaluation=summarize(evaluation,data['annotations'],records,threshold,FOOD) if threshold is not None else None,
                  fixed_threshold_045=summarize(evaluation,data['annotations'],records,.45,FOOD))
    report['coco_bbox'], text = coco_metrics(data,evaluation,records)
    (args.output/'coco-metrics.txt').write_text(text)
    latencies=sorted(r['milliseconds'] for r in records.values())
    report['host_latency_ms']={k:latencies[max(0,math.ceil(pct*len(latencies))-1)] for k,pct in [('p50',.5),('p95',.95)]}
    report['target_met_on_this_scope'] = bool(report['complete_coco_val'] and report['evaluation'] and
        (report['evaluation']['micro']['recall'] or 0)>=.75 and (report['evaluation']['macro_recall'] or 0)>=.75 and (report['evaluation']['micro']['precision'] or 0)>=args.precision_floor)
    if threshold is not None and evaluation:
        import numpy as np
        truth_by_image=defaultdict(set)
        for a in data['annotations']:
            if a['category_id'] in FOOD: truth_by_image[a['image_id']].add(a['category_id'])
        pairs=[]
        for im in evaluation:
            truth=truth_by_image[im['id']]
            predicted={d['category_id'] for d in records[im['id']]['detections'] if d['score']>=threshold}
            pairs.append((len(truth & predicted),len(truth)))
        pairs=np.array(pairs);rng=np.random.default_rng(2026);samples=[]
        for _ in range(1000):
            tp,n=pairs[rng.integers(0,len(pairs),len(pairs))].sum(axis=0)
            if n: samples.append(float(tp/n))
        report['evaluation_recall_image_bootstrap_95']=np.quantile(samples,[.025,.975]).tolist() if samples else None
    report['limitations']=['COCO val may have influenced upstream model development; not an independent kitchen test.',
        'COCO has only five supported ingredient classes; other foods are not exhaustively annotated.',
        'Image-label recall and box AP/AR are different metrics. Counts exclude crowd-labeled image/class pairs.',
        'Host PyTorch timings are not mobile Core ML timings. Model loading and decode excluded.',
        'No scene-group metadata: hash split cannot rule out near-duplicate scene leakage.']
    (args.output/'summary.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:report[k] for k in ['model','threshold','target_met_on_this_scope','host_latency_ms']},indent=2))

if __name__=='__main__':
    main()
