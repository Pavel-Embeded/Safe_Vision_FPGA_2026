"""Audit raw UART bytes independently of the exercising script's verdict."""
import argparse, hashlib, json, sys
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('capture',type=Path);ap.add_argument('--kind',choices=['transitions','recovery'],required=True);a=ap.parse_args()
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
if a.kind=='transitions':
 tr=[r for r in rows if r['kind']=='transition'];manual=[r for r in tr if r['mode']=='uart_next'];auto=[r for r in tr if r['mode']=='auto']
 assert len(manual)==100 and len(auto)==1 and values('C:NEXT=1')==[0]*100
 slots=values('B:SLOT?');gens=values('B:GEN?');lat=values('B:LATENCY?')
 assert len(slots)==len(gens)==102 and len(lat)==100
 for i,r in enumerate(manual):
  assert r['index']==i and r['slot']==slots[i+1]and r['generation']==gens[i+1]and r['reported_next_first_pixel_ms']==lat[i]
  assert slots[i+1]==(slots[i]+1)%4 and gens[i+1]==(gens[i]+1)%256
 delta=(gens[-1]-gens[-2])%256;assert 4<=delta<=6 and slots[-1]==(slots[-2]+delta)%4 and auto[0]['commits']==delta
 assert values('C:AUTO?')==[1]and values('C:PERIOD?')==[5]
 assert acks[-2]['body']=='C:PERIOD=5'and acks[-1]['body']=='C:AUTO=1'
 assert c['uart_next_commits']==100 and c['auto_commits']==delta and c['settings_restored']and len(health)==102
 result.update(accepted=True,uart_next_commits=100,auto_commits=delta,settings_restored=True,physical_button_test=False,reported_next_first_pixel_ms_min=min(lat),reported_next_first_pixel_ms_max=max(lat),emergency_latency_test=False)
else:
 assert values('C:RECOVER=1')==[0]
 ob=[r for r in rows if r['kind']=='recovery_observation'];assert ob
 seq=[r for r in acks if r['body']in{'B:RECOVERY?','B:CACHE?','B:RETRIES?'}]
 # Health checks surround this contiguous three-query polling region.
 start=next(i for i,r in enumerate(acks)if r['body']=='C:RECOVER=1')+1
 for i,r in enumerate(ob):
  triple=acks[start+3*i:start+3*i+3]
  assert [x['body']for x in triple]==['B:RECOVERY?','B:CACHE?','B:RETRIES?']
  assert [x['value']for x in triple]==[r['state'],r['cache'],r['retries']]
 assert any(0<r['state']<5 for r in ob)and any(r['cache']!=15 for r in ob)
 assert ob[-1]['state']==0 and ob[-1]['cache']==15 and not any(r['state']==5 for r in ob)
 retained=[r for r in rows if r['kind']=='retained_configuration']
 wanted={'A:BRTPC':65,'A:CONTRAST':136,'A:SCALESEL':2,'C:VOL':50,'C:PERIOD':10,'C:AUTO':0}
 assert {r['name']:r['actual']for r in retained}==wanted
 for r in retained:assert r['expected']==wanted[r['name']]and values(r['name']+'?')==[r['actual']]
 assert c['software_recovery_requests']==1 and c['cache_clear_observed']and c['busy_observed']and c['retained_configuration_fields']==6 and c['defaults_restored']
 ms=c['controller_recovery_observed_ms'];request=acks[start-1]['elapsed_ms']
 assert abs(ms-ob[-1]['since_request_ms'])<=5
 late=[r for r in ob if r['since_request_ms']>5000 and(r['state']!=0 or r['cache']!=15)]
 assert not late or ms>5000
 assert len(health)==4
 result.update(functional_recovery_passed=True,retained_configuration_fields=6,defaults_restored=True,controller_recovery_observed_ms=ms,handbook_5s_target_passed=(ms<=5000 and not late),late_incomplete_observations=[{'since_request_ms':r['since_request_ms'],'state':r['state'],'cache':r['cache']}for r in late],physical_fault_injection=False,physical_recovery_latency_verified=False,all_requirements_passed=False)
(P/(a.kind+'.audit.json')).write_bytes((json.dumps(result,indent=2)+'\n').encode());print(json.dumps(result,indent=2))
