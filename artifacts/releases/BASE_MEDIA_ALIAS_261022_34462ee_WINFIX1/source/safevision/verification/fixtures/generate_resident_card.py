"""Deterministic card image. Pillow independently decodes BMP reference frames.

The small FAT32 geometry tests RTL protocols, not a real formatted card.
Four early broken files precede four distinct images on descending cluster chains.
Generated megabyte fixtures stay in the isolated simulation directory.
"""
import argparse,io,json,struct
from pathlib import Path
from PIL import Image

def generate(out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    card=bytearray(8192*512)
    def le(pos,val,n=4):card[pos:pos+n]=val.to_bytes(n,'little')
    # DBR: FAT at LBA1..2, data/root at LBA3, 32 sectors per cluster.
    card[0:3]=b'\xeb\x58\x90';card[3:11]=b'SVTEST  '
    le(11,512,2);card[13]=32;le(14,1,2);card[16]=1;le(32,8192)
    le(36,2);le(44,2);card[510:512]=b'\x55\xaa'
    le(512,0x0ffffff8);le(516,0xffffffff);le(520,0x0fffffff)
    def entry(i,name,clus,size):
        p=3*512+i*32;card[p:p+11]=name.encode('ascii');card[p+11]=0x20
        le(p+20,clus>>16,2);le(p+26,clus&65535,2);le(p+28,size)
    # Invalid signatures with legal names and a finite stream.
    le(512+3*4,0x0fffffff)
    for i in range(4):entry(i,f'SV{i+1:04d}  BMP',3,54)
    for image in range(4):
        top_down=bool(image&1);base=4+image*57
        raw=bytearray()
        for disk_y in range(480):
            y=disk_y if top_down else 479-disk_y
            for x in range(640):
                r=(x+image*53)&255;g=(y*7+image*31)&255;b=(x^y^(image*67))&255
                raw.extend((b,g,r))
        data=struct.pack('<2sIHHI',b'BM',54+len(raw),0,0,54)
        data+=struct.pack('<IiiHHIIiiII',40,640,-480 if top_down else 480,1,24,0,len(raw),0,0,0,0)+raw
        entry(4+image,f'SV{image+5:04d}  BMP',base+56,len(data))
        for c in range(base,base+57):le(512+c*4,c-1 if c>base else 0x0fffffff)
        for sector in range((len(data)+511)//512):
            c=base+56-sector//32;lba=3+(c-2)*32+sector%32
            payload=data[sector*512:sector*512+512]
            card[lba*512:lba*512+len(payload)]=payload
        # A separate BMP decoder supplies the expected raster and RGB channels.
        decoded=Image.open(io.BytesIO(data)).convert('RGB')
        pixels=list(decoded.get_flattened_data() if hasattr(decoded,'get_flattened_data') else decoded.getdata())
        words=[]
        for n in range(0,len(pixels),2):
            pair=[]
            for r,g,b in pixels[n:n+2]:pair.append((r>>3)<<11|(g>>2)<<5|(b>>3))
            words.append(f'{pair[0]|pair[1]<<16:08x}\n')
        (out/f'expected{image}.mem').write_text(''.join(words),encoding='ascii')
    (out/'resident_card.mem').write_text(''.join(f'{b:02x}\n' for b in card),encoding='ascii')
    (out/'fixture.json').write_text(json.dumps({'oracle':'Pillow BMP decoder','images':4,
      'rejected_prefix':4,'chain':'descending','top_down':[False,True,False,True]},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',required=True);generate(p.parse_args().output)
