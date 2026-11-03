"""Accuracy-first grocery classifier; official val selects weights, test is separate.
This does not train a detector and must not be reported as multi-object count accuracy.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import time
import torch
from torch import nn
from torch.utils.data import Dataset,DataLoader
from torchvision import models,transforms
from PIL import Image,ImageOps

class Grocery(Dataset):
    def __init__(self,root,rows,size,training=False):
        self.root,self.rows,self.size=root,rows,size
        self.augment=transforms.Compose([transforms.RandomHorizontalFlip(),transforms.ColorJitter(.15,.15,.1,.02)]) if training else lambda x:x
    def __len__(self): return len(self.rows)
    def __getitem__(self,index):
        row=self.rows[index]
        with Image.open(self.root/row['file']) as source:
            image=ImageOps.exif_transpose(source).convert('RGB')
        image=self.augment(image)
        # Match the existing Vision classifier's scaleFit contract: preserve aspect, black padding.
        image=ImageOps.pad(image,(self.size,self.size),method=Image.Resampling.BILINEAR,color=(0,0,0))
        x=transforms.functional.to_tensor(image)
        x=transforms.functional.normalize(x,[.485,.456,.406],[.229,.224,.225])
        return x,row['label']

def make_model(arch,classes,pretrained=True):
    if arch=='efficientnet_v2_s':
        model=models.efficientnet_v2_s(weights=models.EfficientNet_V2_S_Weights.IMAGENET1K_V1 if pretrained else None)
    else:
        model=models.mobilenet_v3_large(weights=models.MobileNet_V3_Large_Weights.IMAGENET1K_V2 if pretrained else None)
    model.classifier[-1]=nn.Linear(model.classifier[-1].in_features,classes)
    return model

@torch.inference_mode()
def evaluate(model,loader,device,labels):
    model.eval(); rows=[]; correct=Counter(); total=Counter()
    for x,y in loader:
        probabilities=model(x.to(device)).softmax(-1).cpu()
        for target,p in zip(y.tolist(),probabilities):
            top=p.topk(min(3,len(labels))).indices.tolist()
            total[target]+=1;correct[target]+=top[0]==target
            rows.append(dict(expected=labels[str(target)],predicted=labels[str(top[0])],top3=[labels[str(c)] for c in top],confidence=float(p[top[0]])))
    if not rows: raise ValueError('Empty evaluation split')
    recall={labels[str(c)]:correct[c]/n for c,n in total.items()}
    n=len(rows);k=sum(correct.values());rate=k/n
    # Wilson interval on images; correlated same-store photos can make it optimistic.
    z=1.96;den=1+z*z/n;center=(rate+z*z/(2*n))/den;delta=z*((rate*(1-rate)/n+z*z/(4*n*n))**.5)/den
    return dict(images=n,top1_micro_recall=rate,macro_recall=sum(recall.values())/len(recall),
                top3_recall=sum(r['expected'] in r['top3'] for r in rows)/n,
                per_class_recall=recall,per_class_support={labels[str(c)]:n for c,n in total.items()},
                image_wilson_95=[center-delta,center+delta],predictions=rows)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('mode',choices=['train','test'])
    p.add_argument('--data',type=Path,default=Path('vision-data/grocery'))
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--arch',choices=['efficientnet_v2_s','mobilenet_v3_large'],default='efficientnet_v2_s')
    p.add_argument('--epochs',type=int,default=20)
    p.add_argument('--size',type=int,default=384)
    p.add_argument('--batch-size',type=int,default=8)
    p.add_argument('--device',choices=['cpu','mps','cuda','auto'],default='auto')
    p.add_argument('--smoke',action='store_true',help='Allow incomplete corpus; never mark target achieved')
    args=p.parse_args()
    if min(args.epochs,args.size,args.batch_size)<=0:p.error('Positive epochs, size and batch required')
    audit=json.loads((args.data/'audit.json').read_text())
    if audit['exact_cross_split_duplicates']:raise ValueError('Split leakage')
    if not audit['complete'] and not args.smoke:raise ValueError('Incomplete corpus; run grocery.py without a limit')
    labels=audit['labels'];count=len(labels)
    if set(map(int,labels))!=set(range(count)):raise ValueError('Class IDs must be contiguous')
    device=args.device
    if device=='auto':device='cuda' if torch.cuda.is_available() else 'mps' if torch.backends.mps.is_available() else 'cpu'
    random.seed(2026);torch.manual_seed(2026)
    args.output.mkdir(parents=True,exist_ok=True)
    checkpoint=args.output/'best.pt'
    def loader(split,train=False):
        return DataLoader(Grocery(args.data,audit['splits'][split],args.size,train),batch_size=args.batch_size,shuffle=train,num_workers=0)
    if args.mode=='train':
        if checkpoint.exists():raise ValueError('Output contains a checkpoint; choose another run directory')
        model=make_model(args.arch,count).to(device)
        # Low learning rate on pretrained features, higher rate on replacement head.
        optimizer=torch.optim.AdamW([{'params':model.features.parameters(),'lr':2e-5},{'params':model.classifier.parameters(),'lr':2e-4}],weight_decay=1e-4)
        criterion=nn.CrossEntropyLoss(label_smoothing=.05)
        best=-1;history=[]
        train_loader=loader('train',True);val_loader=loader('val')
        for epoch in range(args.epochs):
            model.train();loss_sum=0;started=time.perf_counter()
            for x,y in train_loader:
                optimizer.zero_grad(set_to_none=True)
                loss=criterion(model(x.to(device)),y.to(device));loss.backward();optimizer.step()
                loss_sum+=loss.item()*len(y)
            metrics=evaluate(model,val_loader,device,labels)
            history.append(dict(epoch=epoch+1,loss=loss_sum/len(train_loader.dataset),validation_macro_recall=metrics['macro_recall'],seconds=time.perf_counter()-started))
            print(history[-1],flush=True)
            if metrics['macro_recall']>best:
                best=metrics['macro_recall']
                torch.save(dict(state=model.cpu().state_dict(),arch=args.arch,size=args.size,labels=labels,
                                dataset_revision=audit['revision'],complete=audit['complete'],epoch=epoch+1),checkpoint)
                model.to(device)
            (args.output/'history.json').write_text(json.dumps(history,indent=2)+'\n')
    else:
        saved=torch.load(checkpoint,map_location='cpu',weights_only=True)
        if saved['dataset_revision']!=audit['revision'] or saved['labels']!=labels:raise ValueError('Checkpoint/dataset mismatch')
        args.size=saved['size']
        model=make_model(saved['arch'],count,False).to(device);model.load_state_dict(saved['state'])
        result=evaluate(model,loader('test'),device,labels)
        result['target_met']=bool(saved['complete'] and audit['complete'] and result['top1_micro_recall']>=.75 and result['macro_recall']>=.75)
        result['limitations']=['Single foreground class labels: not exhaustive multi-ingredient or counting evaluation.',
                              'Official split and exact-byte duplicate audit; near duplicates and pretraining overlap not ruled out.',
                              'Model is not yet exported or integrated; app thresholds and alias filtering require separate end-to-end validation.']
        (args.output/'test-summary.json').write_text(json.dumps(result,indent=2)+'\n')
        print({k:v for k,v in result.items() if k not in ['predictions','per_class_recall','per_class_support']})

if __name__=='__main__':main()
