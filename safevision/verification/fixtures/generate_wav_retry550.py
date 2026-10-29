
import argparse,struct,json
from pathlib import Path
def generate(out):
 out=Path(out);out.mkdir(parents=True,exist_ok=True);disk=bytearray(128*512);N=600
 def lba(c):return 16+c-2
 def entry(i,name,c,size):
  p=16*512+i*32;disk[p:p+11]=name;disk[p+11]=32;struct.pack_into('<H',disk,p+26,c);struct.pack_into('<I',disk,p+28,size)
 struct.pack_into('<I',disk,512+2*4,0x0fffffff)
 entry(0,b'BROKEN  WAV',4,54);entry(1,b'BADFMT  WAV',5,54)
 for c in (4,5):struct.pack_into('<I',disk,512+c*4,0x0fffffff)
 disk[lba(4)*512:lba(4)*512+4]=b'NOPE'
 disk[lba(5)*512:lba(5)*512+4]=b'RIFF'
 gold=[((((n*73+19)&65535)<<16)|((n*41+17)&65535)) for n in range(N)]
 pcm=b''.join(struct.pack('<I',v) for v in gold);fmt=struct.pack('<HHIIHH',1,2,48000,192000,4,16)

 body=b'WAVEfmt '+struct.pack('<I',16)+fmt+b'JUNK'+struct.pack('<I',601)+bytes([0x61])*601+b'\0data'+struct.pack('<I',len(pcm))+pcm
 wave=b'RIFF'+struct.pack('<I',len(body))+body;chain=[16,28,17,29,18,30]
 for i,c in enumerate(chain):
  struct.pack_into('<I',disk,512+c*4,chain[i+1] if i+1<len(chain) else 0x0fffffff)
  blob=wave[i*512:(i+1)*512];disk[lba(c)*512:lba(c)*512+len(blob)]=blob
 entry(2,b'ANYNAME WAV',chain[0],len(wave))
 (out/'wav_retry_disk.mem').write_text(''.join(f'{b:02x}\n' for b in disk),encoding='ascii')
 (out/'wav_retry_pcm.mem').write_text(''.join(f'{v:08x}\n' for v in gold),encoding='ascii')
 (out/'wav_retry550.reference.json').write_text(json.dumps(dict(PCM_per_track=N,primary=dict(cluster=4,size=54),bad_candidates=[4,5],valid_name='ANYNAME.WAV',valid_cluster_chain=chain,wav_size=len(wave),oracle='struct RIFF/PCM data; independent signed stereo integer formula'),indent=2)+'\n')
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);generate(ap.parse_args().output)
