


import argparse, struct
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);a=ap.parse_args()
r=Path(a.output);r.mkdir(parents=True,exist_ok=True)
def w(name,text):(r/name).write_text(text,encoding='utf-8')

N=2000;disk=bytearray(128*512);gold=[]
def lba(c):return 16+c-2
for g in range(4):
 pcm=bytearray()
 for i in range(N):
  a=((i*41+g*1001)&65535)-32768;b=((i*73+g*2003)&65535)-32768
  pcm+=struct.pack('<hh',a,b);gold.append(((b&65535)<<16)|(a&65535))
 fmt=struct.pack('<HHIIHH',1,2,48000,192000,4,16)
 body=b'WAVE'+b'fmt '+struct.pack('<I',16)+fmt+b'JUNK'+struct.pack('<I',1)+b'a\0'+b'data'+struct.pack('<I',len(pcm))+pcm
 wav=b'RIFF'+struct.pack('<I',len(body))+body
 chain=[16+g+4*k for k in range((len(wav)+511)//512)]
 for k,c in enumerate(chain):
  disk[lba(c)*512:lba(c)*512+min(512,len(wav)-k*512)]=wav[k*512:(k+1)*512]
  struct.pack_into('<I',disk,512+c*4,chain[k+1] if k+1<len(chain) else 0x0fffffff)
 keys=[1,1000,9000,9999]
 for i in range(28):
  key=keys[i-24] if i>=24 else 2+i
  ent=bytearray(32);ent[:11]=f'SV{key:04d}  WAV'.encode();ent[11]=32
  struct.pack_into('<H',ent,26,chain[0] if i==24+g else 4)
  struct.pack_into('<I',ent,28,len(wav) if i==24+g else 44)

  if i<24 or i==24+g:disk[16*512+i*32:16*512+(i+1)*32]=ent
struct.pack_into('<I',disk,512+2*4,3);struct.pack_into('<I',disk,512+3*4,0xfffffff)
w('audio_disk_unaligned.mem','\n'.join(f'{b:02x}' for b in disk)+'\n')
w('audio_pcm_unaligned.mem','\n'.join(f'{b:08x}' for b in gold)+'\n')
