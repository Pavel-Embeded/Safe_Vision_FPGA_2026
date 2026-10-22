"""Independent audit of actual 26101802 UART configuration transactions."""
import argparse,hashlib,json,sys
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('capture',type=Path);a=ap.parse_args()
P=a.capture.resolve();R=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(R/'safevision/tools'));from decode_v3_uart import frames,ACK
rows=[json.loads(s)for s in(P/'trace.jsonl').read_text(encoding='utf-8-sig').splitlines()]
raw=(P/'rx.bin').read_bytes();assert raw==b''.join(bytes.fromhex(r['hex'])for r in rows if r['kind']=='rx')
assert not any(r['kind'] in {'error','failure_restore_attempted','failure_restore_error'}for r in rows)
assert rows[-1]['kind']=='closed'and rows[-1]['exit_code']==0
pending=None;buf=b'';acks=[];matched=False
for r in rows:
 if r['kind']=='tx':
  assert pending is None
  wire=bytes.fromhex(r['hex']);f=frames(wire)
  assert len(f)==1 and f[0]['checksum_ok']and f[0]['body']==r['body']and f[0]['offset']==0 and f[0]['end']==len(wire)
  if not matched:assert r['body']=='B:DIAG=0'
  pending=r;buf=b''
 elif r['kind']=='rx'and pending:buf+=bytes.fromhex(r['hex'])
 elif r['kind']=='ack':
  assert pending and pending['body']==r['body']and 0<=r['elapsed_ms']-pending['elapsed_ms']<2000
  f=[f for f in frames(buf)if ACK.fullmatch(f['body'])];assert len(f)==1 and f[0]['checksum_ok']
  code,value=map(lambda x:int(x,16),ACK.fullmatch(f[0]['body']).groups())
  assert code==r['code']==0 and value==r['value']
  if not matched:assert value==0x26101802;matched=True
  acks.append(r);pending=None
assert pending is None and matched
f=frames(raw);assert all(x['checksum_ok']for x in f)
assert sum(bool(ACK.fullmatch(x['body']))for x in f)==len(acks)
defaults=[r for r in rows if r['kind']=='default_case']
expected={'A:BRTPC':80,'A:BRIGHT':60,'A:CONTRAST':128,'A:SCALESEL':0,'C:VOL':70,'C:PERIOD':5,'C:AUTO':1,'C:MENU':0}
assert len(defaults)==8 and {r['name']:r['actual']for r in defaults}==expected
cases=[r for r in rows if r['kind']=='configuration_case'];assert len(cases)==40
for r in cases:
 if r['name']=='A:BRTPC':assert r['raw_offset']==2*r['requested']-100 and r['actual']==r['requested']
 elif r['name']!='scaler_geometry':assert r['actual']==r['requested']
assert {r['requested']for r in cases if r['name']=='A:BRTPC'}=={0,5,50,80,95,100}
assert {(r['algorithm'],r['scale'])for r in cases if r['name']=='scaler_geometry'}=={(a,s)for a in range(2)for s in range(4)}
health=[r for r in rows if r['kind']=='health'];assert len(health)==42
for r in health:
 v=r['values'];assert v['CACHE']==15
 assert all(v[q]==0 for q in('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW'))
 assert v['FAULT']==0 or(v['FAULT']==7 and v['WAVFALLBACK']>0)
complete=[r for r in rows if r['kind']=='complete'];assert len(complete)==1 and complete[0]['configuration_cases']==40 and complete[0]['defaults_restored']
result=dict(accepted=True,firmware_id='26101802',scope='actual UART identity, startup defaults, setting/readback and reported health counters',ordered_valid_acks=len(acks),startup_defaults=8,configuration_cases=40,health_observations=42,defaults_restored=True,physical_display_verified=False,physical_audio_verified=False,github_uploaded=False,rx_sha256=hashlib.sha256(raw).hexdigest(),trace_sha256=hashlib.sha256((P/'trace.jsonl').read_bytes()).hexdigest())
(P/'configuration.audit.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print(json.dumps(result,indent=2))
