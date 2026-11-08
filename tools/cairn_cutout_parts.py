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
HIDDEN = {('side', 'chest'): (91, 107, 13, 11), ('side', 'belly'): (92, 121, 13, 8)}

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
 owns={name:opaque&(labels==NAMES.index(name)) for name in NAMES}
 fits={name:_capped(name,_fit_ellipse(owns[name])) for name in NAMES}
 parts={}
 for name in NAMES:
  own=owns[name]; cx,cy=centers.get(name,p['chest'])
  # The stone completed: an ellipse fitted to the part's visible pixels (a mostly hidden part
  # borrows its twin's radii round its authored centre), shaded like the painted stones, no
  # outline of its own except on the hidden side (the renderer inks the frame's outer edge).
  twin=name.replace('near_','far_') if name.startswith('near_') else name.replace('far_','near_')
  fit=fits[name]
  if twin!=name and fits.get(twin) and (fit is None or own.sum()<0.7*owns[twin].sum()):
   fit=(cx,cy,fits[twin][2],fits[twin][3])
  if (view,name) in HIDDEN: fit=HIDDEN[(view,name)]
  red='glove' in name
  hidden=np.zeros(a.shape,np.uint8)
  if name!='head' and fit is not None:
   hidden=_stone(a.shape[:2],fit,red,own)
  motion=hidden.copy();motion[own]=a[own]
  h=hidden.copy(); allowed=opaque&(ranks>rank[name]);h[~allowed]=0
  h[own]=a[own]
  bbox=Image.fromarray(motion).getbbox()
  if bbox is None: # concealed part: tiny patch behind the torso, never a missing API entry
   bbox=(round(cx)-1,round(cy)-1,round(cx)+2,round(cy)+2)
   h=np.zeros(a.shape,np.uint8);h[bbox[1]:bbox[3],bbox[0]:bbox[2]]=STONE;motion=h.copy()
  image=Image.fromarray(h).crop(bbox)
  still=Image.fromarray((opaque*255).astype(np.uint8)).crop(bbox)
  parts[name]={'image':image,'motion_image':Image.fromarray(motion).crop(bbox),'still':still,'pivot':(cx-bbox[0],cy-bbox[1]),'center':(cx,cy),'order':rank[name],'bounds':bbox}
 return src,parts

# The largest stone a part may be completed to (rx, ry): a band's fit or a borrowed twin's
# can run wild (a leg band holding a bit of the other leg, the forearm with its cloth).
CAPS={'glove':(7,7),'shoulder':(8,8),'upperarm':(7,8),'forearm':(8,8),'thigh':(9,8),'shin':(9,8),
      'foot':(10,5),'chest':(18,12),'belly':(15,9),'base':(18,8)}

def _capped(name,fit):
 if fit is None: return None
 kind=name.split('_')[-1]
 cx,cy,rx,ry=fit; mx,my=CAPS.get(kind,(9,9))
 return cx,cy,min(rx,mx),min(ry,my)

def _fit_ellipse(own):
 """(cx, cy, rx, ry) of the round stone whose visible pixels are `own`: the widest rows give
 the centre column and rx, the narrowing of the rows above and below the height (least
 squares on |y - cy| = ry sqrt(1 - (w/2rx)^2)); a band cut from a stone's middle (no
 narrowing) is taken as the widest part of a stone 0.6 rx tall at least."""
 ys=np.nonzero(own.any(axis=1))[0]
 if len(ys)<3: return None
 rows=[(y,int(np.nonzero(own[y])[0].min()),int(np.nonzero(own[y])[0].max())) for y in ys]
 widths={y:r-l+1 for y,l,r in rows}; wmax=max(widths.values())
 if wmax<6: return None
 cx=float(np.median([(l+r)/2 for y,l,r in rows if widths[y]>=0.7*wmax]))
 rx=wmax/2
 ywide=float(np.mean([y for y,l,r in rows if widths[y]>=0.9*wmax]))
 A=[];b=[]
 for y,l,r in rows:
  h=widths[y]/2
  if h>=0.92*rx: continue
  u=np.sqrt(max(0.0,1-(h/rx)**2)); A.append((1.0,(-1.0 if y<ywide else 1.0)*u)); b.append(float(y))
 cy,ry=ywide,None
 if len(A)>=3:
  (cy_,ry_),*_=np.linalg.lstsq(np.array(A),np.array(b),rcond=None)
  if ry_>0: cy,ry=float(cy_),float(ry_)
 span=ys.max()-ys.min()+1
 if ry is None or ry<span/2 or ry>1.4*rx+2 or not ys.min()-ry*0.5<=cy<=ys.max()+ry*0.5:
  ry=max(span/2+2.5,0.6*rx); cy=ywide   # a band from the stone's middle, or a solve gone wild
 ry=min(ry,1.4*rx+2)
 return cx,cy,rx,ry

def _stone(shape,fit,red,own):
 """The completed stone as RGBA (alpha 254: a fill pixel, so the renderer can tell it from
 painted ones): a light top-left, a dark lower-right crescent and a darker rim, in the
 still's own colours; its ink ring only where no painted ink of the part is next to it."""
 cx,cy,rx,ry=fit
 def ell(d,fill,dx=0.0,dy=0.0,shrink=0.0):
  d.ellipse((cx-rx+shrink+dx,cy-ry+shrink+dy,cx+rx-shrink+dx,cy+ry-shrink+dy),fill=fill)
 base,light,dark,rim=((214,38,42,254),(238,84,70,254),(165,21,49,254),(118,14,46,254)) if red else (STONE[:3]+(254,),LIGHT[:3]+(254,),DARK[:3]+(254,),(40,46,62,254))
 im=Image.new('RGBA',shape[::-1]); d=ImageDraw.Draw(im)
 ell(d,rim); ell(d,dark,shrink=1); ell(d,base,dx=-0.6,dy=-1.0,shrink=1.6); ell(d,light,dx=-1.2,dy=-2.0,shrink=max(2.6,min(rx,ry)*0.45))
 ring=Image.new('L',shape[::-1]); ImageDraw.Draw(ring).ellipse((cx-rx,cy-ry,cx+rx,cy+ry),outline=255,width=1)
 ring=np.array(ring)>0
 # the painted part's ink: a ring pixel touching it (8-neighbours) would double the outline
 a=np.array(im)
 padm=np.pad(own,1)
 near_own=np.zeros(own.shape,bool)
 for dy in (-1,0,1):
  for dx in (-1,0,1):
   near_own|=padm[1+dy:own.shape[0]+1+dy,1+dx:own.shape[1]+1+dx]
 keep=ring&~near_own
 a[keep]=INK[:3]+(254,)
 return a

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
   p['image'].save(dest/(name+'.png'));p['motion_image'].save(dest/(name+'_complete.png'));meta[name]={k:v for k,v in p.items() if k not in ('image','motion_image','still')}
  (dest/'parts.json').write_text(json.dumps(meta,indent=2))
  rec=reconstruct(view);rec.save(ART/(view+'_reconstructed.png'))
  diff=np.any(np.array(src)!=np.array(rec),axis=2)
  report[view]={'changed_pixels':int(diff.sum()),'parts':len(parts)}
  atlas.alpha_composite(src,(i*192,0));atlas.alpha_composite(rec,(i*192,192))
 atlas.resize((1920,768),Image.Resampling.NEAREST).save(ART/'reconstruction-preview.png')
 (ART/'extraction-report.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(report))
if __name__=='__main__':main()
