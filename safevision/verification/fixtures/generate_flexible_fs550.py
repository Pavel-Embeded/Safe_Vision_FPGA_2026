


import argparse, io, json, struct
from pathlib import Path
from PIL import Image

def generate(out,bad_primary=False):
 out=Path(out);out.mkdir(parents=True,exist_ok=True)
 card=bytearray(8192*512)
 def le(pos,value,n=4):card[pos:pos+n]=value.to_bytes(n,'little')
 card[:11]=b'\xeb\x58\x90SVTEST  ';le(11,512,2);card[13]=32;le(14,1,2);card[16]=1
 le(32,8192);le(36,2);le(44,2);card[510:512]=b'\x55\xaa'
 le(512,0x0ffffff8);le(516,0xffffffff);le(520,0x0fffffff)
 entries=[];file_records=[];next_cluster=4
 def add(name,alias,blob):
  nonlocal next_cluster
  c=next_cluster;next_cluster+=1;le(512+c*4,0x0fffffff)
  start=(3+(c-2)*32)*512;card[start:start+len(blob)]=blob
  raw_alias=alias.encode('ascii');assert len(raw_alias)==11
  checksum=0
  for byte in raw_alias:checksum=(((checksum&1)<<7)+(checksum>>1)+byte)&255
  encoded=name.encode('utf-16le');units=list(struct.unpack('<'+'H'*(len(encoded)//2),encoded))
  chunks=[units[n:n+13] for n in range(0,len(units),13)]
  for order in range(len(chunks),0,-1):
   b=bytearray(32);b[0]=order|(64 if order==len(chunks) else 0);b[11]=15;b[13]=checksum
   chunk=chunks[order-1]
   if len(chunk)<13:chunk=chunk+[0]+[65535]*(12-len(chunk))
   for off,u in zip((1,3,5,7,9,14,16,18,20,22,24,28,30),chunk):struct.pack_into('<H',b,off,u)
   entries.append(b)
  b=bytearray(32);b[:11]=raw_alias;b[11]=32;struct.pack_into('<H',b,26,c);struct.pack_into('<I',b,28,len(blob))
  record=dict(name=name,cluster=c,size=len(blob),key=len(entries)+1);file_records.append(record);entries.append(b)
  return record

 broken=add('000 broken picture.bmp','BROKEN~1BMP',b'XX'+bytes(52))
 pcm=[];waves=[];N=600
 for track in range(4):
  pairs=[((((73*n+2003*track)&65535)<<16)|((41*n+1001*track)&65535)) for n in range(N)]
  pcm+=pairs;payload=b''.join(struct.pack('<I',v) for v in pairs)
  fmt=struct.pack('<HHIIHH',1,2,48000,192000,4,16)
  body=b'WAVEfmt '+struct.pack('<I',16)+fmt+b'JUNK'+struct.pack('<I',1)+b'x\0data'+struct.pack('<I',len(payload))+payload
  waves.append(b'RIFF'+struct.pack('<I',len(body))+body)

 add('First unrelated.wav','FIRST~1 WAV',waves[2])
 add('Second unrelated.wav','SECOND~1WAV',waves[3])
 add('Third unrelated.wav','THIRD~1 WAV',waves[1])
 images=[('A portrait.bmp',(7,13),False),('AB emoji_\U0001f600.bmp',(13,7),True),('SV001.BMP',(9,9),False),('测试图片一.bmp',(1,1),True),('测试图片二.bmp',(11,5),False)]
 image_records=[]
 for slot,(name,(w,h),top) in enumerate(images):
  raw=bytearray()
  for disk_y in range(h):
   y=disk_y if top else h-1-disk_y
   for x in range(w):raw.extend(((x^y^slot*67)&255,(y*7+slot*31)&255,(x+slot*53)&255))
   raw.extend(bytes((-w*3)%4))
  bmp=struct.pack('<2sIHHI',b'BM',54+len(raw),0,0,54)+struct.pack('<IiiHHIIiiII',40,w,-h if top else h,1,24,0,len(raw),0,0,0,0)+raw
  image_records.append(add(name,f'IMAGE{slot}~1BMP',bmp))
  if slot<4:
   decoded=Image.open(io.BytesIO(bmp)).convert('RGB')
   dw,dh=(640,max(1,h*640//w)) if w*480>=h*640 else (max(1,w*480//h),480)
   px=(640-dw)//2;py=(480-dh)//2;words=[]
   for y in range(480):
    for x in range(0,640,2):
     pair=[]
     for xx in (x,x+1):
      if px<=xx<px+dw and py<=y<py+dh:
       r,g,b=decoded.getpixel(((xx-px)*w//dw,(y-py)*h//dh));pair.append((r>>3)<<11|(g>>2)<<5|(b>>3))
      else:pair.append(0)
     words.append(f'{pair[0]|pair[1]<<16:08x}\n')
   (out/f'expected{slot}.mem').write_text(''.join(words),encoding='ascii')
 for n in range(16):add(f'Z unused companion {n:02}.wav',f'UN{n:02}~1  WAV',waves[0])
 add('SV0001.WAV','SV0001  WAV',waves[0])
 exact_a=add('a PORTRAIT.wav','AMATCH~1WAV',(b'NOPE'+waves[0][4:]) if bad_primary else waves[0])
 exact_chinese=add('测试图片一.WAV','CHINA~1 WAV',waves[2])
 directory=b''.join(entries)+bytes(32)
 assert len(directory)<32*512
 card[3*512:3*512+len(directory)]=directory
 (out/'resident_card.mem').write_text(''.join(f'{b:02x}\n' for b in card),encoding='ascii')

 tracks=[2 if bad_primary else 0,3,1,2]
 (out/'lifecycle_pcm.mem').write_text(''.join(f'{pcm[t*N+n]:08x}\n' for t in tracks for n in range(N)),encoding='ascii')
 keys=sum(r['key']<<(16*i) for i,r in enumerate(image_records[:4]))
 (out/'flexible_metadata.mem').write_text(f'{keys:016x}\n{broken["key"]:016x}\n',encoding='ascii')
 (out/'flexible_fs550.reference.json').write_text(json.dumps(dict(oracle='Pillow BMP decode + independent rational floor resampling + struct PCM; FAT fields explicit little endian',images=image_records,broken=broken,keys_hex=f'{keys:016x}',selected_audio_tracks=tracks,pairing_contract='full UTF16 stem only, otherwise directory ordinal; numeric SV001/SV0001 is not an exact stem',files=file_records,entries=len(entries),PCM_per_track=N),indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);generate(ap.parse_args().output)
