


import argparse,io,json,struct
from pathlib import Path
from PIL import Image
def generate(out):
 out=Path(out);out.mkdir(parents=True,exist_ok=True);card=bytearray(16384*512)
 def le(p,n,s=4):card[p:p+s]=int(n).to_bytes(s,'little')
 card[0:3]=b'\xeb\x58\x90';card[3:11]=b'SVMIXED ';le(11,512,2);card[13]=32;le(14,1,2);card[16]=1;le(32,16384);le(36,4);le(44,2);card[510:512]=b'\x55\xaa'
 le(512,0x0ffffff8);le(516,0xffffffff);le(520,0x0fffffff);le(524,0x0fffffff)
 def entry(i,clus,n):
  p=2560+32*i;card[p:p+11]=f'SV{i+1:04d}  BMP'.encode();card[p+11]=32;le(p+20,clus>>16,2);le(p+26,clus&65535,2);le(p+28,n)
 for i in range(4):entry(i,3,54)
 cursor=4;total=0;cases=[(1,1,False),(1,1080,True),(1920,1,False),(1920,1080,True)]
 for image,(w,h,td)in enumerate(cases):
  stride=(w*3+3)//4*4;raw=bytearray()
  for row in range(h):
   y=row if td else h-1-row
   for x in range(w):raw.extend(((x^y^(image*67))&255,(y*7+image*31)&255,(x+image*53)&255))
   raw.extend(b'\xad'*(stride-w*3))
  data=struct.pack('<2sIHHI',b'BM',54+len(raw),0,0,54)+struct.pack('<IiiHHIIiiII',40,w,-h if td else h,1,24,0,len(raw),0,0,0,0)+raw
  total+=len(data);n=(len(data)+16383)//16384;base=cursor;cursor+=n;assert cursor<512
  entry(4+image,base+n-1,len(data))
  for c in range(base,base+n):le(512+4*c,c-1 if c>base else 0x0fffffff)
  for sector in range((len(data)+511)//512):
   c=base+n-1-sector//32;lba=5+(c-2)*32+sector%32;payload=data[sector*512:sector*512+512];card[512*lba:512*lba+len(payload)]=payload
  decoded=Image.open(io.BytesIO(data)).convert('RGB');src=decoded.load()
  if w*480>=h*640:dw=640;dh=max(1,h*640//w)
  else:dh=480;dw=max(1,w*480//h)
  left=(640-dw)//2;top=(480-dh)//2;pixels=[]
  for y in range(480):
   for x in range(640):
    if left<=x<left+dw and top<=y<top+dh:r,g,b=src[(x-left)*w//dw,(y-top)*h//dh];pixels.append((r>>3)<<11|(g>>2)<<5|(b>>3))
    else:pixels.append(0)
  (out/f'expected{image}.mem').write_text(''.join(f'{pixels[k]|pixels[k+1]<<16:08x}\n'for k in range(0,len(pixels),2)),encoding='ascii')
 (out/'resident_card.mem').write_text(''.join(f'{b:02x}\n'for b in card),encoding='ascii')
 (out/'payload_bytes.mem').write_text(f'{total:08x}\n',encoding='ascii')
 (out/'fixture.json').write_text(json.dumps(dict(oracle='Pillow decode + independent rational nearest-neighbor reference',cases=cases,source_bytes=total,normalized_pixels=4*640*480,cluster_chain='descending',invalid_prefix_files=4),indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',required=True);generate(p.parse_args().output)
