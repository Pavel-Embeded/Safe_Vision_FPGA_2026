"""Reconstruct actual automatic dwell tests from raw checked UART transactions."""
import argparse,hashlib,json,sys
from pathlib import Path

def audit(p):
 p=Path(p);root=Path(__file__).resolve().parents[3]
 sys.path.insert(0,str(root/'safevision/tools'));from decode_v3_uart import frames,ACK
 rows=[json.loads(s)for s in(p/'trace.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 raw=(p/'rx.bin').read_bytes();assert raw==b''.join(bytes.fromhex(r['hex'])for r in rows if r['kind']=='rx')
 assert rows[-1]['kind']=='closed'and rows[-1]['exit_code']==0
 assert not any(r['kind']in {'error','failure_restore_attempted','failure_restore_error'}for r in rows)
 pending=None;buf=b'';acks=[];triples=[];health=[];cursor=0
 for r in rows:
  if r['kind']=='tx':
   assert pending is None
   wire=bytes.fromhex(r['hex']);f=frames(wire)
   assert len(f)==1 and f[0]['checksum_ok']and f[0]['body']==r['body']and f[0]['offset']==0 and f[0]['end']==len(wire)
   pending=r;buf=b''
  elif r['kind']=='rx'and pending:buf+=bytes.fromhex(r['hex'])
  elif r['kind']=='ack':
   assert pending and pending['body']==r['body']and 0<=r['elapsed_ms']-pending['elapsed_ms']<2000
   f=[f for f in frames(buf)if ACK.fullmatch(f['body'])];assert len(f)==1 and f[0]['checksum_ok']
   code,value=[int(x,16)for x in ACK.fullmatch(f[0]['body']).groups()]
   assert code==r['code']==0 and value==r['value'];acks.append(r);pending=None
  elif r['kind']=='period_sample':
   q=acks[-3:];assert [a['body']for a in q]==['B:GEN?','B:SLOT?','B:GEN?']
   v=r['values'];assert q[0]['value']==q[2]['value']==v['generation']and q[1]['value']==v['slot']
   assert 0<=r['elapsed_ms']-q[-1]['elapsed_ms']<=5 and 0<=r['elapsed_ms']-v['sample_ms']<=5
   triples.append(r)
  elif r['kind']=='health':
   names=['CACHE','FAULT','LEVEL','WAVFALLBACK','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW']
   q=acks[-len(names):];assert[a['body']for a in q]==['B:'+n+'?'for n in names]
   assert {n:a['value']for n,a in zip(names,q)}==r['values'];v=r['values']
   assert v['CACHE']==15 and v['WAVFALLBACK']==0
   assert all(v[n]==0 for n in names if n not in {'CACHE','WAVFALLBACK'});health.append(r)
 assert pending is None and acks[0]['body']=='B:DIAG=0'and acks[0]['value']==0x26101802
 parsed=frames(raw);cursor=0
 for f in parsed:assert f['checksum_ok']and f['offset']==cursor;cursor=f['end']
 assert cursor==len(raw)and sum(bool(ACK.fullmatch(f['body']))for f in parsed)==len(acks)
 begin=[r for r in rows if r['kind']=='period_begin'];end=[r for r in rows if r['kind']=='period_complete']
 assert [r['period']for r in begin]==[2,5,10,30]==[r['period']for r in end]
 result=[]
 for b,e in zip(begin,end):
  period=b['period'];samples=[r for r in triples if r['period']==period]
  assert samples and samples[0]['values']['generation']==b['generation']and samples[0]['values']['slot']==b['slot']
  changed=[]
  for old,new in zip(samples,samples[1:]):
   o,n=old['values'],new['values'];delta=(n['generation']-o['generation'])%256
   gap=new['elapsed_ms']-old['elapsed_ms']
   # Windows may deschedule the observer between unchanged samples. Bound
   # every gap by one requested dwell; retain the strict observation bound
   # at each real transition, where it determines interval precision.
   assert 0<gap<period*1000
   if delta:
    assert gap<=450
    assert delta==1 and n['slot']==(o['slot']+1)%4;changed.append(new)
   else:assert n['slot']==o['slot']
  declared=[r for r in rows if r['kind']=='period_commit'and r['period']==period]
  assert len(changed)==len(declared)==e['commits']==3 and e['intervals']==2
  intervals=[]
  for i,(sample,c)in enumerate(zip(changed,declared)):
   v=sample['values'];assert(c['index'],c['generation'],c['slot'],c['sample_ms'])==(i,v['generation'],v['slot'],v['sample_ms'])
   interval=0 if i==0 else v['sample_ms']-changed[i-1]['values']['sample_ms']
   assert c['interval_ms']==interval
   if i:
    # Independent actual BASE clock/raster/Fade contract, not rounded60Hz.
    expected_ms=period*1000+32*800*525/25185185*1000
    assert abs(interval-expected_ms)<=250;intervals.append(interval)
  result.append(dict(period_seconds=period,auto_commits=3,measured_intervals_ms=intervals,nominal_period_plus_fade_ms=expected_ms))
 def values(body):return[r['value']for r in acks if r['body']==body]
 assert values('A:FADE?')==[1]
 assert values('C:PERIOD?')==[5,2,5,10,30,5]
 assert values('C:AUTO?')==[1,1,1,1,1,1]
 c=[r for r in rows if r['kind']=='complete'];assert len(c)==1
 assert c[0]['period_cases']==4 and c[0]['auto_commits']==12 and c[0]['measured_intervals']==8 and c[0]['settings_restored']
 assert len(health)==14
 return dict(accepted=True,firmware_id='26101802',ordered_valid_acks=len(acks),period_cases=result,health_observations=len(health),settings_restored=True,rx_sha256=hashlib.sha256(raw).hexdigest(),trace_sha256=hashlib.sha256((p/'trace.jsonl').read_bytes()).hexdigest(),physical_display_verified=False,physical_audio_verified=False,github_uploaded=False)

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('capture',type=Path);a=ap.parse_args();j=audit(a.capture)
 (a.capture/'periods.audit.json').write_bytes((json.dumps(j,indent=2)+'\n').encode());print(json.dumps(j,indent=2))
