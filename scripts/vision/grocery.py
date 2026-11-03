"""Fetch a revision-pinned GroceryStoreDataset and audit exact split leakage.
Only original smartphone photos are used, not iconic product images/descriptions.
"""
import argparse
import concurrent.futures
import csv
import hashlib
import json
from pathlib import Path
import urllib.request
from download import fetch

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--root',type=Path,default=Path('vision-data/grocery'))
    p.add_argument('--limit-per-split',type=int,default=0,help='Download smoke subset only')
    args=p.parse_args()
    args.root.mkdir(parents=True,exist_ok=True)
    revision_file=args.root/'revision.txt'
    if not revision_file.exists():
        with urllib.request.urlopen('https://api.github.com/repos/marcusklasson/GroceryStoreDataset/commits/master',timeout=60) as response:
            revision=json.load(response)['sha']
        revision_file.write_text(revision+'\n')
    revision=revision_file.read_text().strip()
    base=f'https://raw.githubusercontent.com/marcusklasson/GroceryStoreDataset/{revision}/'
    for name in ['classes.csv','train.txt','val.txt','test.txt']:
        fetch(base+'dataset/'+name,args.root/name)
    fetch(base+'LICENSE',args.root/'LICENSE')
    with (args.root/'classes.csv').open() as source:
        classes=list(csv.DictReader(source))
    # Keep source taxonomy, including separate juices/dairy. Never map juice to raw fruit.
    labels={int(r['Coarse Class ID (int)']):r['Coarse Class Name (str)'].lower().replace('-',' ') for r in classes}
    rows={}
    for split in ['train','val','test']:
        rows[split]=[dict(file=r[0].strip(),fine=int(r[1]),label=int(r[2])) for r in csv.reader((args.root/f'{split}.txt').open()) if r]
        if args.limit_per_split:
            rows[split]=rows[split][:args.limit_per_split]
    paths=[r['file'] for items in rows.values() for r in items]
    if len(set(paths))!=len(paths): raise ValueError('Repeated path across official split lists')
    def download(path):
        target=(args.root/path).resolve()
        if not target.is_relative_to(args.root.resolve()): raise ValueError('Unsafe source path')
        target.parent.mkdir(parents=True,exist_ok=True)
        return path,fetch(base+'dataset/'+path,target)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        hashes=dict(pool.map(download,paths))
    seen={}
    duplicates=[]
    for split,items in rows.items():
        for r in items:
            h=hashes[r['file']]
            if h in seen and seen[h][0]!=split: duplicates.append([seen[h],(split,r['file'])])
            seen[h]=(split,r['file'])
    audit=dict(revision=revision,labels=labels,splits=rows,sha256=hashes,exact_cross_split_duplicates=duplicates,
               complete=not bool(args.limit_per_split),source='https://github.com/marcusklasson/GroceryStoreDataset')
    (args.root/'audit.json').write_text(json.dumps(audit,indent=2)+'\n')
    print({s:len(v) for s,v in rows.items()},'classes=',len(labels),'exact leakage=',len(duplicates),flush=True)
    if duplicates: raise ValueError('Exact duplicate images cross splits; audit.json records them. Resolve before training.')

if __name__=='__main__': main()
