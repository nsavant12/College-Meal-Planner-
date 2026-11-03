"""Prepare official split for NativeClassifierEvaluation; preserve export label mapping."""
import argparse
import json
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('--data', type=Path, default=Path('vision-data/grocery'))
p.add_argument('--split', choices=['val','test'], default='val')
p.add_argument('--output', type=Path, required=True)
args = p.parse_args()
audit = json.loads((args.data/'audit.json').read_text())
if not audit['complete'] or audit['exact_cross_split_duplicates']:
    raise ValueError('Requires complete, audited corpus')
aliases = {'aubergine':'eggplant','carrots':'carrot','yoghurt':'yogurt','pepper':'bell pepper'}
rows = []
for row in audit['splits'][args.split]:
    label = audit['labels'][str(row['label'])]
    rows.append({'file':str((args.data/row['file']).resolve()), 'expected':aliases.get(label,label)})
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(rows, indent=2)+'\n')
print(len(rows), 'images')
