"""Four independently decoded BMPs plus fragmented exact PCM WAV companions."""
from pathlib import Path
import argparse,importlib.util,struct,json
R=Path(__file__).resolve().parents[3]
def generate(out):
 out=Path(out)
 spec=importlib.util.spec_from_file_location('resident_fixture',R/'safevision/verification/fixtures/generate_resident_card.py')
 base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base);base.generate(out)
 card=bytearray(int(x,16) for x in (out/'resident_card.mem').read_text().split())
 def le(p,v,n=4):card[p:p+n]=v.to_bytes(n,'little')
 def ent(i,key,c,size):
  p=3*512+i*32;card[p:p+11]=f'SV{key:04d}  WAV'.encode();card[p+11]=32;le(p+20,c>>16,2);le(p+26,c&65535,2);le(p+28,size)
 for i in range(8,24):ent(i,100+i,3,44)
 gold=[];N=6000
 for slot in range(4):
  pcm=bytearray()
  for i in range(N):
   left=((41*i+slot*1001)&65535)-32768;right=((73*i+slot*2003)&65535)-32768
   pcm+=struct.pack('<hh',left,right);gold.append(((right&65535)<<16)|(left&65535))
  fmt=struct.pack('<HHIIHH',1,2,48000,192000,4,16)
  body=b'WAVEfmt '+struct.pack('<I',16)+fmt+b'JUNK'+struct.pack('<I',1)+b'a\0data'+struct.pack('<I',len(pcm))+pcm
  wave=b'RIFF'+struct.pack('<I',len(body))+body
  chain=[232+slot,240+slot]
  ent(24+slot,5+slot,chain[0],len(wave))
  for j,c in enumerate(chain):le(512+c*4,chain[j+1] if j+1<len(chain) else 0x0fffffff)
  for sector in range((len(wave)+511)//512):
   lba=3+(chain[sector//32]-2)*32+sector%32
   payload=wave[sector*512:sector*512+512];card[lba*512:lba*512+len(payload)]=payload
 (out/'resident_card.mem').write_text(''.join(f'{b:02x}\n' for b in card),encoding='ascii')
 (out/'lifecycle_pcm.mem').write_text(''.join(f'{w:08x}\n' for w in gold),encoding='ascii')
 (out/'lifecycle_fixture.json').write_text(json.dumps({'frames':4,'PCM_per_track':N,'WAV_context_phase':2,'fragmented_clusters':[[232+i,240+i] for i in range(4)],'unmatched_WAV_prefix':16},indent=2))
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);generate(ap.parse_args().output)
