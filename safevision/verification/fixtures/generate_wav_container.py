
from pathlib import Path
import argparse,io,json,random,struct,wave
def chunk(name,data):return name+struct.pack('<I',len(data))+data+(b'\0' if len(data)&1 else b'')
def riff(chunks):
 body=b'WAVE'+b''.join(chunks)
 return b'RIFF'+struct.pack('<I',len(body))+body
def main():
 a=argparse.ArgumentParser();a.add_argument('--output',required=True);out=Path(a.parse_args().output);out.mkdir(parents=True,exist_ok=True)
 rng=random.Random(0x5afe021);cases=[]
 fmt=struct.pack('<HHIIHH',1,2,48000,192000,4,16)
 for i in range(160):
  extra_len=[0,1,2,15,16,17,31,32,33,47,48,63,64,100,239,496][i%16]
  payload=b''.join(struct.pack('<hh',rng.randrange(-32768,32768),rng.randrange(-32768,32768)) for _ in range(1+i%127))
  before=[chunk(b'JUNK',rng.randbytes(i%35)),chunk(b'LIST',rng.randbytes((i*7)%19))]
  after=[chunk(b'fact',rng.randbytes((i*11)%21)),chunk(b'JUNK',b'')] if i%2 else []
  data=riff(before+[chunk(b'fmt ',fmt+rng.randbytes(extra_len)),chunk(b'data',payload)]+after)

  with wave.open(io.BytesIO(data),'rb') as w:
   assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.readframes(10000))==(2,2,48000,payload)
  if i%3==0:data+=rng.randbytes(i%17)
  pairs=list(struct.unpack('<'+'I'*(len(payload)//4),payload));cases.append((f'legal_fmt{16+extra_len}_tail{i%2}',data,pairs,0))
 for size in [0,1,2,3,5,6,7,9,15]:
  data=riff([chunk(b'fmt ',fmt),chunk(b'data',bytes(size))]);cases.append((f'partial_or_empty_{size}',data,[],1))

 for claim in [0xfffffffc,0xfffffff8,0xffffffff,0xffffffe0]:
  data=riff([chunk(b'fmt ',fmt)])+b'data'+struct.pack('<I',claim)+bytes(range(1,9))
  data=data[:4]+struct.pack('<I',len(data)-8)+data[8:];cases.append((f'overflow_{claim:x}',data,[],1))
 for field,value in [(0,3),(2,1),(4,44100),(14,24)]:
  bad=bytearray(fmt);struct.pack_into('<I' if field==4 else '<H',bad,field,value)
  cases.append((f'bad_fmt_{field}',riff([chunk(b'fmt ',bad),chunk(b'data',b'1234')]),[],1))
 cases.append(('data_before_fmt',riff([chunk(b'data',b'1234'),chunk(b'fmt ',fmt)]),[],1))
 good=riff([chunk(b'fmt ',fmt),chunk(b'data',b'1234')])
 for cut in [1,5,11,20,35,43,46]:cases.append((f'truncated_{cut}',good[:cut],[],1))
 bad=bytearray(good);bad[8:12]=b'NOPE';cases.append(('bad_wave',bytes(bad),[],1))
 bad=bytearray(good);bad[4:8]=struct.pack('<I',0xffffffff);cases.append(('riff_overflow',bytes(bad),[],1))
 data=riff([b'JUNK'+struct.pack('<I',0xfffffff0)+b'xxxx',chunk(b'fmt ',fmt),chunk(b'data',b'1234')]);cases.append(('unknown_overflow',data,[],1))
 disk=[];gold=[];desc=[];meta=[]
 for name,data,pairs,err in cases:
  desc += [len(disk),len(data),len(gold),len(pairs),err]
  meta.append({'name':name,'length':len(data),'pairs':len(pairs),'error':bool(err)})
  disk.extend(data);gold.extend(pairs)
 (out/'compact_disk.mem').write_text('\n'.join(f'{x:02x}' for x in disk)+'\n')
 (out/'compact_pcm.mem').write_text('\n'.join(f'{x:08x}' for x in gold)+'\n')
 (out/'compact_desc.mem').write_text('\n'.join(f'{x:08x}' for x in [len(cases)]+desc)+'\n')
 (out/'compact_fixture.json').write_text(json.dumps({'cases':meta,'data_bytes':len(disk),'gold_pairs':len(gold)},indent=2))
 print(f'Independent WAV fixture cases={len(cases)} bytes={len(disk)} PCM={len(gold)}')
if __name__=='__main__':main()
