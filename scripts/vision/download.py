"""Download the official COCO validation corpus; stream, verify ZIP CRC, safe extraction."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

URLS = {
    'val2017.zip': 'https://s3.amazonaws.com/images.cocodataset.org/zips/val2017.zip',
    'annotations_trainval2017.zip': 'https://s3.amazonaws.com/images.cocodataset.org/annotations/annotations_trainval2017.zip',
}

def fetch(url, destination):
    if not destination.exists():
        partial = destination.with_suffix(destination.suffix + '.partial')
        print('Downloading', url, flush=True)
        with urllib.request.urlopen(url, timeout=120) as response, partial.open('wb') as out:
            while block := response.read(1024 * 1024):
                out.write(block)
        partial.replace(destination)
    h = hashlib.sha256()
    with destination.open('rb') as source:
        while block := source.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, default=Path('vision-data/coco'))
    p.add_argument('--check-urls', action='store_true', help='Check archive availability without downloading')
    args = p.parse_args()
    if args.check_urls:
        for url in URLS.values():
            with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60) as response:
                print(response.status, response.headers.get('Content-Length'), url)
        return
    args.root.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, url in URLS.items():
        archive = args.root / name
        digest = fetch(url, archive)
        with zipfile.ZipFile(archive) as z:
            if z.testzip() is not None:
                raise ValueError('Corrupt archive: ' + name)
            for entry in z.infolist():
                # Only validation instances needed; don't unpack the training annotations.
                if name.startswith('annotations') and entry.filename != 'annotations/instances_val2017.json':
                    continue
                target = (args.root / entry.filename).resolve()
                if not target.is_relative_to(args.root.resolve()):
                    raise ValueError('Unsafe archive path')
                z.extract(entry, args.root)
        manifest[name] = dict(url=url, sha256=digest, bytes=archive.stat().st_size)
    data = json.loads((args.root/'annotations/instances_val2017.json').read_text())
    if len(data['images']) != 5000:
        raise ValueError('Expected the complete 5,000-image validation set')
    for image in data['images']:
        if not (args.root/'val2017'/image['file_name']).is_file():
            raise ValueError('Missing image: ' + image['file_name'])
    (args.root/'download-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('Ready: 5,000 images, official instance annotations; hashes recorded (not publisher signatures).')

if __name__ == '__main__':
    main()
