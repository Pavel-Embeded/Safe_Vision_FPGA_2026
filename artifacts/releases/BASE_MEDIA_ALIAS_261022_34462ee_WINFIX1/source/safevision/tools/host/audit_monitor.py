"""Independent raw serial/transaction audit. No display or audio assertion."""
import argparse,json,hashlib,sys
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('capture',type=Path);ap.add_argument('--expected-id',default='26101802');a=ap.parse_args()
R=Path(__file__).resolve().parents[3];P=a.capture.resolve()
sys.path.insert(0,str(R/'safevision/tools'));from decode_v3_uart import frames,ACK
rows=[json.loads(x) for x in (P/'trace.jsonl').read_text(encoding='utf-8-sig').splitlines()]
raw=(P/'rx.bin').read_bytes();assert raw==b''.join(bytes.fromhex(r['hex']) for r in rows if r['kind']=='rx')
assert not any(r['kind']=='error' for r in rows)
assert rows[-1]['kind']=='closed' and rows[-1]['exit_code']==0
pending=None;buf=b'';acks=[];tx_bytes=0
for r in rows:
 if r['kind']=='tx':
  assert pending is None
  wire=bytes.fromhex(r['hex']);parsed=frames(wire)
  assert len(parsed)==1 and parsed[0]['checksum_ok'] and parsed[0]['body']==r['body'] and parsed[0]['offset']==0 and parsed[0]['end']==len(wire)
  assert r['body']=='B:DIAG=0' or r['body'].endswith('?'),'monitor attempted a setting change'
  pending=r;buf=b'';tx_bytes+=len(wire)
 elif r['kind']=='rx' and pending is not None:buf+=bytes.fromhex(r['hex'])
 elif r['kind']=='ack':
  assert pending and r['body']==pending['body'] and 0<=r['elapsed_ms']-pending['elapsed_ms']<2000
  got=[f for f in frames(buf) if ACK.fullmatch(f['body'])];assert len(got)==1 and got[0]['checksum_ok']
  code,value=(int(x,16) for x in ACK.fullmatch(got[0]['body']).groups())
  assert code==r['code']==0 and value==r['value'];acks.append(r);pending=None
assert pending is None
parsed=frames(raw);assert all(f['checksum_ok'] for f in parsed)
assert sum(bool(ACK.fullmatch(f['body'])) for f in parsed)==len(acks)
by_name={}
for r in acks:by_name.setdefault(r['body'],[]).append(r['value'])
assert by_name['B:DIAG=0']==[int(a.expected_id,16)] and by_name['C:AUTO?']==[1] and by_name['C:PERIOD?']==[5]
samples=[r for r in rows if r['kind']=='observation'];assert len(samples)>=2
queries=('STATUS','CACHE','FAULT','LEVEL','SLOT','GEN','INTEGRITY','PRESENTATION','VUNDERFLOW','UNDERFLOW','OVERFLOW','EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')
for q in queries:assert [r['values'][q] for r in samples]==by_name['B:'+q+'?']
zeros=('LEVEL','INTEGRITY','PRESENTATION','VUNDERFLOW','UNDERFLOW','OVERFLOW','EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')
for r in samples:
 v=r['values'];assert v['CACHE']==15 and v['STATUS']==7
 assert all(v[q]==0 for q in zeros)
commits=0
slot_reads=[r for r in acks if r['body']=='B:SLOT?'];gen_reads=[r for r in acks if r['body']=='B:GEN?']
phase=(samples[0]['values']['SLOT']-samples[0]['values']['GEN'])%4
non_atomic=[]
for i,r in enumerate(samples):
 # These are separate UART transactions, not a single atomic snapshot. A
 # commit between SLOT and GEN can leave SLOT one generation behind GEN.
 gap=gen_reads[i]['elapsed_ms']-slot_reads[i]['elapsed_ms'];assert 0<=gap<100
 v=r['values'];now=(v['GEN']+phase)%4
 assert v['SLOT'] in (now,(now-1)%4)
 if v['SLOT']!=now:non_atomic.append(dict(index=i,slot=v['SLOT'],generation=v['GEN'],query_gap_ms=gap))
for old,new in zip(samples,samples[1:]):
 delta=(new['values']['GEN']-old['values']['GEN'])%256
 assert 1<=delta<=6
 commits+=delta
duration=next(r for r in rows if r['kind']=='monitor_duration');assert duration['observations']==len(samples)
elapsed=samples[-1]['elapsed_ms']-samples[0]['elapsed_ms']
j=dict(schema=1,accepted=True,firmware_id=a.expected_id,read_only_serial_scope=True,requested_seconds=duration['requested_seconds'],
 duration_ms=duration['duration_ms'],observations=len(samples),ordered_valid_acks=len(acks),tx_bytes=tx_bytes,rx_bytes=len(raw),
 observed_auto_commits=commits,observed_interval_mean_seconds=elapsed/1000/commits,zero_counters=list(zeros),
 fault_codes=sorted(set(r['values']['FAULT'] for r in samples)),cache_mask=15,player_state=7,
 separate_query_commit_boundaries=non_atomic,
 rx_sha256=hashlib.sha256(raw).hexdigest(),trace_sha256=hashlib.sha256((P/'trace.jsonl').read_bytes()).hexdigest(),
 physical_screen_or_audio_claim=False,full_hardware_acceptance=False,uart_identity_verified=a.expected_id,github_upload_performed=False)
(P/'serial.audit.json').write_bytes((json.dumps(j,indent=2)+'\n').encode());print(json.dumps(j,indent=2))
