#!/usr/bin/env python3
"""Audit the app's real predictions. No ML dependencies; no invented annotations.
Usage: evaluate-recognition.py results.json [--annotations annotations.json] --output report.json
Annotations: list of {file, scene, split, counts?, boxes?}. Boxes: {name, xywh}.
Coordinates are normalized bottom-left after EXIF orientation. Count annotations
must enumerate every countable class including zero for an exhaustive scene.
"""
import argparse
import json
import math
import random
from collections import defaultdict
from pathlib import Path


def divide(a, b):
    return a / b if b else None


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(p * len(ordered)) - 1)]


def labels(rows, field="detected"):
    totals = [0, 0, 0]
    classes = defaultdict(lambda: [0, 0, 0])
    exact = negatives = false_positives = 0
    for row in rows:
        expected, predicted = set(row["expected"]), set(row[field])
        exact += expected == predicted
        negatives += not expected
        false_positives += not expected and bool(predicted)
        for name in expected | predicted:
            index = 0 if name in expected & predicted else (1 if name in predicted else 2)
            totals[index] += 1
            classes[name][index] += 1
    def metrics(values):
        tp, fp, fn = values
        return dict(tp=tp, fp=fp, fn=fn, precision=divide(tp, tp+fp), recall=divide(tp, tp+fn), f1=divide(2*tp, 2*tp+fp+fn))
    per_class = {k: metrics(v) for k, v in sorted(classes.items())}
    f1s = [v["f1"] for v in per_class.values() if v["f1"] is not None]
    return dict(micro=metrics(totals), macro_f1=divide(sum(f1s), len(f1s)), per_class=per_class,
                exact_set_accuracy=divide(exact, len(rows)), negative_scenes=negatives,
                negative_false_positive_rate=divide(false_positives, negatives))


def iou(a, b):
    x = max(0, min(a[0]+a[2], b[0]+b[2])-max(a[0], b[0]))
    y = max(0, min(a[1]+a[3], b[1]+b[3])-max(a[1], b[1]))
    intersection = x*y
    return divide(intersection, a[2]*a[3]+b[2]*b[3]-intersection) or 0


def localization(rows, annotations):
    annotated = [r for r in rows if "boxes" in annotations.get(r["file"], {}) and r.get("detectorStatus") == "available"]
    if not annotated:
        return None
    output = {}
    for threshold in [0.5, 0.75]:
        tp = fp = fn = 0
        for row in annotated:
            truth = annotations[row["file"]]["boxes"]
            matched = set()
            for box in sorted(row.get("boxes", []), key=lambda b: -b["score"]):
                candidates = [(iou(box["xywh"], gt["xywh"]), i) for i, gt in enumerate(truth)
                              if i not in matched and gt["name"] == box["name"]]
                score, index = max(candidates, default=(0, -1))
                if score >= threshold:
                    tp += 1
                    matched.add(index)
                else:
                    fp += 1
            fn += len(truth)-len(matched)
        output[str(threshold)] = dict(tp=tp, fp=fp, fn=fn, precision=divide(tp,tp+fp), recall=divide(tp,tp+fn))
    return dict(scenes=len(annotated), operating_point=output,
                note="Post-NMS operating-point metrics, not COCO mAP. Export raw ranked proposals to compute AP.")


def counts(rows, annotations):
    errors = []
    positive_errors = []
    under = over = exact = 0
    for row in rows:
        truth = annotations.get(row["file"], {}).get("counts")
        if truth is None or row.get("detectorStatus") != "available":
            continue
        predicted = row.get("counts", {})
        for name in annotations[row["file"]].get("countScope", set(truth) | set(predicted)):
            difference = predicted.get(name, 0) - truth.get(name, 0)
            errors.append(abs(difference))
            if truth.get(name, 0) > 0:
                positive_errors.append(abs(difference))
            under += difference < 0
            over += difference > 0
            exact += difference == 0
    return None if not errors else dict(pairs=len(errors), mae=sum(errors)/len(errors),
                                        positive_pairs=len(positive_errors), positive_mae=divide(sum(positive_errors), len(positive_errors)),
                                        positive_exact_rate=divide(sum(v == 0 for v in positive_errors), len(positive_errors)),
                                        exact_rate=exact/len(errors), undercount_rate=under/len(errors), overcount_rate=over/len(errors))


def report(rows, annotations):
    if not rows:
        raise ValueError("No evaluated scenes")
    ids = [r["file"] for r in rows]
    if len(set(ids)) != len(ids):
        raise ValueError("Duplicate files: aggregate repeated timing separately from accuracy")
    for record in list(rows) + list(annotations.values()):
        if any(not isinstance(v, int) or isinstance(v, bool) or v < 0 for v in record.get("counts", {}).values()):
            raise ValueError("Counts must be nonnegative integers")
        for box in record.get("boxes", []):
            b = box["xywh"]
            if len(b) != 4 or not all(math.isfinite(v) for v in b) or b[0] < 0 or b[1] < 0 or b[2] <= 0 or b[3] <= 0 or b[0]+b[2] > 1.000001 or b[1]+b[3] > 1.000001:
                raise ValueError("Invalid normalized box")
            if "score" in box and (not math.isfinite(box["score"]) or not 0 <= box["score"] <= 1):
                raise ValueError("Invalid detection score")
    groups = defaultdict(list)
    for row in rows:
        annotation = annotations.get(row["file"], {})
        if annotation.get("split", row["split"]) != row["split"]:
            raise ValueError("Prediction/annotation split mismatch")
        groups[annotation.get("scene", row["file"])].append(row)
        for key in ["milliseconds", "initialMilliseconds"]:
            if key in row and (not math.isfinite(row[key]) or row[key] < 0):
                raise ValueError("Invalid latency")
    if any(len({r["split"] for r in group}) > 1 for group in groups.values()):
        raise ValueError("Scene leakage across splits")
    # Resample whole scenes, not ingredient labels or crops. Six fixtures remain
    # too small for deployment decisions regardless of the interval reported.
    rng = random.Random(0)
    group_list = list(groups.values())
    samples = []
    for _ in range(1000):
        sample = [r for _ in group_list for r in rng.choice(group_list)]
        score = labels(sample)["micro"]["f1"]
        if score is not None:
            samples.append(score)
    latency = {}
    for key in ["initialMilliseconds", "milliseconds"]:
        values = [r[key] for r in rows if key in r]
        latency[key] = dict(n=len(values), p50=percentile(values, .5), p95=percentile(values, .95), maximum=max(values, default=None))
    return dict(schema_version=1, scenes=len(groups), images=len(rows), classification=labels(rows),
                baseline=labels(rows, "baseline"), by_split={split: labels([r for r in rows if r["split"] == split]) for split in sorted({r["split"] for r in rows})},
                scene_bootstrap_f1_95=[percentile(samples, .025), percentile(samples, .975)], latency=latency,
                failed_regions=sum(r.get("failedRegions", 0) for r in rows),
                detector_status={s: sum(r.get("detectorStatus", "unavailable") == s for r in rows) for s in ["available", "unavailable", "failed"]},
                quantities=counts(rows, annotations), localization=localization(rows, annotations),
                limitations=["Small development/regression corpus; not independent validation.",
                             "Missing count/box ground truth is unmeasured, never zero error.",
                             "Timing includes mixed cold/warm runs; not an iPhone benchmark.",
                             "Freshness, allergens, mass and volume are not evaluated."])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path)
    parser.add_argument("--annotations", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    annotation_rows = json.loads(args.annotations.read_text()) if args.annotations else []
    annotations = {r["file"]: r for r in annotation_rows}
    if len(annotations) != len(annotation_rows):
        raise ValueError("Duplicate annotations")
    result = report(json.loads(args.results.read_text()), annotations)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+"\n")
    print(json.dumps(result["classification"]["micro"]))

if __name__ == "__main__":
    main()
