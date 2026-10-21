"""Audit raw UART bytes independently of the exercising script's verdict."""
import argparse, hashlib, json, sys
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('capture',type=Path);a=ap.parse_args()
P=a.capture.resolve();R=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(R/'safevision/tools'));from decode_v3_uart import frames,ACK
rows=[json.loads(s)for s in(P/'trace.jsonl').read_text(encoding='utf-8-sig').splitlines()]
raw=(P/'rx.bin').read_bytes();assert raw==b''.join(bytes.fromhex(r['hex'])for r in rows if r['kind']=='rx')
assert not any(r['kind']in{'error','failure_restore_attempted','failure_restore_error'}for r in rows)
assert rows[-1]['kind']=='closed'and rows[-1]['exit_code']==0
pending=None;buf=b'';acks=[]
for r in rows:
 if r['kind']=='tx':
  assert pending is None
  wire=bytes.fromhex(r['hex']);f=frames(wire)
  assert len(f)==1 and f[0]['checksum_ok']and f[0]['body']==r['body']and f[0]['offset']==0 and f[0]['end']==len(wire)
  if not acks:assert r['body']=='B:DIAG=0'
  pending=r;buf=b''
 elif r['kind']=='rx'and pending:buf+=bytes.fromhex(r['hex'])
 elif r['kind']=='ack':
  assert pending and pending['body']==r['body']and 0<=r['elapsed_ms']-pending['elapsed_ms']<2000
  f=[f for f in frames(buf)if ACK.fullmatch(f['body'])];assert len(f)==1 and f[0]['checksum_ok']
  code,value=[int(x,16)for x in ACK.fullmatch(f[0]['body']).groups()]
  assert code==r['code']==0 and value==r['value']
  if not acks:assert value==0x26101802
  acks.append(r);pending=None
assert pending is None and all(f['checksum_ok']for f in frames(raw))
assert sum(bool(ACK.fullmatch(f['body']))for f in frames(raw))==len(acks)
def values(body):return [r['value']for r in acks if r['body']==body]
health=[r for r in rows if r['kind']=='health']
for q in ('CACHE','FAULT','LEVEL','WAVFALLBACK','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW'):
 actual=values('B:'+q+'?')
 if q not in ('CACHE','RECOVERY'):assert actual==[r['values'][q]for r in health]
 else:
  it=iter(actual)
  for r in health:assert any(v==r['values'][q]for v in it)
for r in health:
 v=r['values'];assert v['CACHE']==15 and all(v[q]==0 for q in('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW'))
 assert v['FAULT']==0 or(v['FAULT']==7 and v['WAVFALLBACK']>0)
complete=[r for r in rows if r['kind']=='complete'];assert len(complete)==1;c=complete[0]
result=dict(raw_transactions_valid=True,firmware_id='26101802',ordered_valid_acks=len(acks),health_observations=len(health),physical_display_verified=False,physical_audio_verified=False,github_uploaded=False,rx_sha256=hashlib.sha256(raw).hexdigest(),trace_sha256=hashlib.sha256((P/'trace.jsonl').read_bytes()).hexdigest())
starts=[r for r in rows if r['kind']=='geometry_start']
manual=[r for r in rows if r['kind']=='geometry_next'];auto=[r for r in rows if r['kind']=='geometry_auto']
assert len(starts)==8 and len(manual)==32 and len(auto)==8 and len(health)==42
assert values('C:NEXT=1')==[0]*32
position=0
for algorithm in range(2):
 for scale in range(4):
  n=algorithm*4+scale;start=starts[n];end=auto[n]
  assert (start['algorithm'],start['scale'])==(algorithm,scale)==(end['algorithm'],end['scale'])
  # Between geometry_start and next start/complete, all ACKs bind to this case.
  hi=starts[n+1]['elapsed_ms'] if n<7 else next(r['elapsed_ms']for r in rows if r['kind']=='complete')
  aa=[r for r in acks if start['elapsed_ms']<r['elapsed_ms']<hi]
  slots=[start['slot']]+[r['value']for r in aa if r['body']=='B:SLOT?'][:5]
  gens=[start['generation']]+[r['value']for r in aa if r['body']=='B:GEN?'][:5]
  assert len(slots)==len(gens)==6
  for i in range(4):
   r=manual[n*4+i];assert (r['algorithm'],r['scale'],r['index'])==(algorithm,scale,i)
   assert r['slot']==slots[i+1]==(slots[i]+1)%4
   assert r['generation']==gens[i+1]==(gens[i]+1)%256
  delta=(gens[5]-gens[4])%256
  assert 4<=delta<=6 and slots[5]==(slots[4]+delta)%4
  assert end['commits']==delta and end['slot']==slots[5]and end['generation']==gens[5]
  set_scale=[r for r in acks if r['body']=='A:SCALESEL='+str(scale)and r['elapsed_ms']<start['elapsed_ms']]
  set_algo=[r for r in acks if r['body']=='A:SCALER='+str(algorithm)and r['elapsed_ms']<start['elapsed_ms']]
  assert set_scale and set_algo
assert values('A:FADE=1')==[0,0] and values('A:FADE?')==[1]*10
for q,default in [('A:SCALER',0),('A:SCALESEL',0),('A:FADE',1),('C:PERIOD',5),('C:AUTO',1)]:
 assert values(q+'?')[0]==values(q+'?')[-1]==default
assert c['combinations']==8 and c['manual_fade_commits']==32 and c['auto_commits']==sum(r['commits']for r in auto)and c['settings_restored']
result.update(accepted=True,combinations=8,manual_fade_commits=32,auto_commits=c['auto_commits'],settings_restored=True,physical_button_test=False,emergency_latency_test=False)
(P/'geometries.audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2))
