"""Cairn's approved painted cutouts and completed hidden surfaces.

The input stills are immutable source art. Masks are hand-authored in frame pixels;
visible pixels are never repainted. Concealed areas are filled once in the same stone
palette, only underneath an overlapping higher layer, so idle reconstruction is exact.
Run this file to rebuild the part PNGs and inspection atlas. No game sheets are changed.
"""
from pathlib import Path
from dataclasses import dataclass
from functools import lru_cache
import json
import numpy as np
from PIL import Image, ImageDraw
import palette

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/sprites/source/cairn_cutout'
ALIASES = {'down':'front','up':'back','down_side':'front_34','up_side':'back_34'}
NAMES = ['far_foot','far_shin','far_thigh','near_foot','near_shin','near_thigh',
         'far_glove','far_forearm','far_upperarm','far_shoulder','base','belly','chest',
         'near_shoulder','near_upperarm','near_forearm','near_glove','head']
INK=(20,18,30,255); DARK=(64,72,90,255); STONE=(98,106,120,255); LIGHT=(138,144,154,255)

def box(x0,y0,x1,y1): return [(x0,y0),(x1,y0),(x1,y1),(x0,y1)]
# Parts are assigned by these polygons in order; later polygons take precedence.
# Fine seams follow the existing stone boundaries, not generated rig geometry.
PROFILES = {
 'side': dict(head=96, belly=(117,124),base=(123,134), split=94, legs=(134,148,159),
  leftfeet=(84,165),rightfeet=(108,161), chest=(94,106),
  arms=[('far_shoulder',box(94,96,105,106),(99,101)),('far_upperarm',box(99,103,110,116),(104,109)),
        ('far_forearm',box(104,102,114,113),(109,107)),('far_glove',box(104,93,118,107),(110,100)),
        ('near_shoulder',box(72,94,89,105),(82,100)),('near_upperarm',box(72,106,78,122),(76,113)),
        ('near_forearm',[(79,105),(100,105),(100,118),(88,120),(79,120)],(88,111)),
        ('near_glove',[(96,97),(103,96),(104,99),(107,101),(107,110),(96,110)],(102,103))]),
 'front':dict(head=85,belly=(106,115),base=(115,125),split=96,legs=(125,138,150),
  leftfeet=(80,154),rightfeet=(113,154),chest=(96,98),
  arms=[('far_shoulder',box(102,85,117,96),(109,91)),('far_upperarm',box(108,94,121,103),(115,98)),
        ('far_forearm',box(108,99,123,109),(115,104)),('far_glove',box(100,88,112,101),(106,94)),
        ('near_shoulder',box(76,85,89,96),(82,91)),('near_upperarm',box(72,94,84,103),(78,98)),
        ('near_forearm',box(70,99,85,109),(78,104)),('near_glove',box(80,88,94,101),(87,94))]),
 'back':dict(head=96,belly=(117,126),base=(126,136),split=96,legs=(136,149,161),
  leftfeet=(80,165),rightfeet=(113,165),chest=(96,107),
  arms=[('far_glove',box(72,97,81,106),(77,101)),('far_shoulder',box(76,99,86,111),(81,105)),
        ('far_upperarm',box(74,109,84,117),(79,113)),('far_forearm',box(74,114,85,122),(80,118)),
        ('near_glove',box(111,97,119,106),(115,101)),('near_shoulder',box(106,99,116,111),(111,105)),
        ('near_upperarm',box(109,109,120,117),(115,113)),('near_forearm',box(109,114,123,122),(116,118))]),
 'front_34':dict(head=88,belly=(109,117),base=(117,127),split=91,legs=(127,140,151),
  leftfeet=(79,156),rightfeet=(106,153),chest=(92,100),
  arms=[('far_shoulder',box(96,87,107,97),(101,92)),('far_upperarm',box(98,98,110,110),(104,104)),
        ('far_forearm',box(102,95,114,104),(108,100)),('far_glove',box(103,83,118,98),(110,91)),
        ('near_shoulder',box(70,87,85,99),(77,94)),('near_upperarm',box(70,97,83,109),(76,103)),
        ('near_forearm',[(77,101),(90,97),(95,103),(87,111),(77,109)],(85,105)),
        ('near_glove',box(89,88,103,102),(96,95))]),
 'back_34':dict(head=96,belly=(117,126),base=(126,136),split=89,legs=(136,149,161),
  leftfeet=(74,165),rightfeet=(100,165),chest=(86,108),
  arms=[('far_glove',box(67,96,77,106),(72,101)),('far_shoulder',box(70,99,82,111),(76,105)),
        ('far_upperarm',box(70,109,80,116),(75,112)),('far_forearm',box(70,114,80,122),(75,118)),
        ('near_glove',box(101,98,114,110),(108,104)),('near_shoulder',box(91,99,106,111),(98,105)),
        ('near_upperarm',box(97,110,110,117),(103,113)),('near_forearm',box(97,115,109,123),(103,119))]),
}

# Hidden-surface fills that need more than the default rounded body behind a moving limb:
# (view, part) -> (centre x, centre y, radius x, radius y). The side chest keeps its back
# under the shoulder stones, so a jab that swings a shoulder forward shows a body, not a notch.
HIDDEN = {('side', 'chest'): (91, 107, 13, 11), ('side', 'belly'): (92, 121, 11, 6)}

def _prepare(view):
 view=ALIASES.get(view,view); p=PROFILES[view]
 src=Image.open(ART/(view+'.png')).convert('RGBA'); a=np.array(src); opaque=a[:,:,3]>0
 label=Image.new('I',src.size,NAMES.index('chest')); d=ImageDraw.Draw(label)
 centers={'chest':p['chest'],'head':None}
 def region(name,polygon,center):
  d.polygon(polygon,fill=NAMES.index(name));centers[name]=center
 # Legs before torso/arms. Near is the left chain in front views, right in rear views.
 rear=view.startswith('back'); left='far' if rear else 'near'; right='near' if rear else 'far'
 y0,y1,y2=p['legs'];split=p['split']
 for side,x0,x1,foot in [(left,0,split,p['leftfeet']),(right,split+1,191,p['rightfeet'])]:
  fx,fy=foot
  region(side+'_thigh',box(x0,y0,x1,y1-1),(fx,y0+5))
  region(side+'_shin',box(x0,y1,x1,y2-1),(fx,y1+5))
  region(side+'_foot',box(x0,y2,x1,191),foot)
 region('base',box(0,*[p['base'][0]],191,p['base'][1]-1),(p['chest'][0],sum(p['base'])/2))
 region('belly',box(0,p['belly'][0],191,p['belly'][1]-1),(p['chest'][0],sum(p['belly'])/2))
 region('head',box(0,0,191,p['head']-1),(p['chest'][0],p['head']-20))
 for n,poly,c in p['arms']:region(n,poly,c)
 labels=np.array(label)
 # a glove's box also catches stone pixels of the chest or arm behind it: those stay with the
 # body (the chest label), and so does any outline pixel not touching the glove's red
 red=opaque&(a[:,:,0].astype(int)>a[:,:,1].astype(int)+40)
 pad=np.pad(red,1); nearred=red|pad[:-2,1:-1]|pad[2:,1:-1]|pad[1:-1,:-2]|pad[1:-1,2:]
 for gname in ('near_glove','far_glove'):
  g=labels==NAMES.index(gname)
  labels[g&opaque&~nearred]=NAMES.index('chest')
 if view=='side': # the cloth wrapped round the elbow turns with the forearm it ties, not the elbow stone
  red=(a[:,:,0].astype(int)>a[:,:,1].astype(int)+40)&(labels==NAMES.index('near_upperarm'))
  labels[red]=NAMES.index('near_forearm')
 # In front views both gloves sit in front of the torso. Rear gloves sit behind.
 order=list(NAMES)
 if not rear:
  order.remove('far_glove');order.insert(order.index('near_glove'),'far_glove')
 rank={n:i for i,n in enumerate(order)}
 ranks=np.vectorize(lambda k:rank[NAMES[k]])(labels)
 parts={}
 for name in NAMES:
  own=opaque&(labels==NAMES.index(name)); cx,cy=centers.get(name,p['chest'])
  # Rounded concealed stone body, restricted to areas covered by later parts.
  if 'glove' in name: rx,ry=5,6;fill=tuple(palette.LINES['red'][2])+(255,)
  elif 'shoulder' in name:rx,ry=6,6;fill=STONE
  elif 'arm' in name:rx,ry=5,6;fill=STONE
  elif name=='chest':rx,ry=10,10;fill=STONE
  elif name=='belly':rx,ry=8,5;fill=STONE
  elif name=='base':rx,ry=13,5;fill=STONE
  elif name=='head':rx,ry=7,16;fill=STONE
  elif 'foot' in name:rx,ry=7,3;fill=STONE
  else:rx,ry=6,6;fill=STONE
  if (view,name) in HIDDEN: cx,cy,rx,ry=HIDDEN[(view,name)]
  hidden=Image.new('RGBA',src.size); hd=ImageDraw.Draw(hidden)
  hd.ellipse((round(cx-rx),round(cy-ry),round(cx+rx),round(cy+ry)),fill=fill,outline=INK,width=1)
  if name in ('chest','belly','base'): # a lit top and a shaded underside, so a revealed torso reads as stone
   hd.ellipse((round(cx-rx),round(cy-ry),round(cx+rx),round(cy+ry)),fill=DARK,outline=INK,width=1)
   hd.ellipse((round(cx-rx+1),round(cy-ry+1),round(cx+rx-1),round(cy+ry-3)),fill=STONE)
  if 'glove' not in name:hd.ellipse((round(cx-rx+2),round(cy-ry+1),round(cx+rx-2),round(cy)),fill=LIGHT if name not in ('chest','belly','base') else STONE)
  motion=np.array(hidden);motion[own]=a[own]
  h=np.array(hidden); allowed=opaque&(ranks>rank[name]);h[~allowed]=0
  h[own]=a[own]
  full=Image.fromarray(h);bbox=Image.fromarray(motion).getbbox()
  if bbox is None: # concealed part: tiny patch behind the torso, never a missing API entry
   bbox=(round(cx)-1,round(cy)-1,round(cx)+2,round(cy)+2)
   full=Image.new('RGBA',src.size);ImageDraw.Draw(full).ellipse(bbox,fill=STONE,outline=INK)
  image=full.crop(bbox)
  parts[name]={'image':image,'motion_image':Image.fromarray(motion).crop(bbox),'pivot':(cx-bbox[0],cy-bbox[1]),'center':(cx,cy),'order':rank[name],'bounds':bbox}
 return src,parts

@lru_cache(maxsize=5)
def load_parts(view='side'):
 """Return rigid cutouts; caller must not mutate the cached PIL images."""
 return _prepare(view)[1]

def reconstruct(view):
 im=Image.new('RGBA',(192,192))
 for part in sorted(load_parts(view).values(),key=lambda p:p['order']):
  x,y=part['bounds'][:2];im.alpha_composite(part['image'],(x,y))
 return im

def main():
 report={};atlas=Image.new('RGBA',(960,384),(65,70,80,255))
 for i,view in enumerate(PROFILES):
  src,parts=_prepare(view);dest=ART/'parts'/view;dest.mkdir(parents=True,exist_ok=True)
  meta={}
  for name,p in parts.items():
   p['image'].save(dest/(name+'.png'));p['motion_image'].save(dest/(name+'_complete.png'));meta[name]={k:v for k,v in p.items() if k not in ('image','motion_image')}
  (dest/'parts.json').write_text(json.dumps(meta,indent=2))
  rec=reconstruct(view);rec.save(ART/(view+'_reconstructed.png'))
  diff=np.any(np.array(src)!=np.array(rec),axis=2)
  report[view]={'changed_pixels':int(diff.sum()),'parts':len(parts)}
  atlas.alpha_composite(src,(i*192,0));atlas.alpha_composite(rec,(i*192,192))
 atlas.resize((1920,768),Image.Resampling.NEAREST).save(ART/'reconstruction-preview.png')
 (ART/'extraction-report.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(report))
if __name__=='__main__':main()
