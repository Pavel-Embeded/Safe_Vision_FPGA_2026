"""Independently check actual serial transactions; never certify screen/audio."""
import argparse,hashlib,json,re,sys
from pathlib import Path
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--capture',type=Path,required=True);ap.add_argument('--bit',type=Path,required=True)
a=ap.parse_args();R=a.repo.resolve();RUN=a.capture.resolve()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sys.path.insert(0,str(R/'safevision/tools'))
from decode_v3_uart import analyze,frames,ACK
def healthy(v):
 assert v['CACHE']==15
 for q in ('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW'):assert v[q]==0,(q,v[q])
 assert v['FAULT']==0 or (v['FAULT']==7 and v['LEVEL']==0 and v['WAVFALLBACK']>0)
def trace(folder,manual=0,recovery=False):
 rows=[json.loads(s) for s in (folder/'trace.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 raw=(folder/'rx.bin').read_bytes();assert b''.join(bytes.fromhex(r['hex']) for r in rows if r['kind']=='rx')==raw
 assert not any(r['kind']=='error' for r in rows)
 assert rows[-1]['kind']=='closed' and rows[-1]['exit_code']==0
 pending=None;buffer=b'';acks=[];tx_bytes=0
 for row in rows:
  if row['kind']=='tx':
   assert pending is None
   tx=bytes.fromhex(row['hex']);parts=frames(tx);assert len(parts)==1 and parts[0]['checksum_ok'] and parts[0]['body']==row['body'] and parts[0]['offset']==0 and parts[0]['end']==len(tx)
   tx_bytes+=len(tx);pending=row;buffer=b''
  elif row['kind']=='rx' and pending is not None:buffer+=bytes.fromhex(row['hex'])
  elif row['kind']=='ack':
   assert pending is not None and row['body']==pending['body'] and row['elapsed_ms']-pending['elapsed_ms']<2000
   replies=[f for f in frames(buffer) if ACK.fullmatch(f['body'])];assert len(replies)==1 and replies[0]['checksum_ok']
   code,value=(int(x,16) for x in ACK.fullmatch(replies[0]['body']).groups())
   assert code==row['code']==0 and value==row['value'];acks.append(row);pending=None
 assert pending is None
 captured=frames(raw);assert all(x['checksum_ok'] for x in captured)
 assert sum(bool(ACK.fullmatch(x['body'])) for x in captured)==len(acks)
 complete=[r for r in rows if r['kind']=='complete'];assert len(complete)==1 and complete[0]['settings_restored']
 health=[r for r in rows if r['kind']=='health'];assert len(health)>=2
 for h in health:healthy(h['values'])
 record=dict(accepted=True,tx_bytes=tx_bytes,rx_bytes=len(raw),ack_count=len(acks),raw_sha256=sha(folder/'rx.bin'),elapsed_ms=rows[-1]['elapsed_ms'])
 if not recovery:
  slot=next(a['value'] for a in acks if a['body']=='B:SLOT?');gen=next(a['value'] for a in acks if a['body']=='B:GEN?')
  transitions=[r for r in rows if r['kind']=='transition'];m=[r for r in transitions if r['mode']=='manual'];auto=[r for r in transitions if r['mode']=='auto'];assert len(m)==manual and len(auto)==1
  # Link each recorded transition to its two actual query replies.
  pairs=[(a,b) for a,b in zip(acks,acks[1:]) if a['body']=='B:SLOT?' and b['body']=='B:GEN?'];assert len(pairs)==len(transitions)+1
  for i,t in enumerate(transitions):
   a,b=pairs[i+1];assert (t['slot'],t['generation'])==(a['value'],b['value'])
   delta=1 if t['mode']=='manual' else t['commits'];assert delta==1 or 4<=delta<=6
   assert t['slot']==(slot+delta)%4 and t['generation']==(gen+delta)%256
   slot,gen=t['slot'],t['generation']
  record.update(manual_commits=len(m),auto_commits=auto[0]['commits'])
 else:
  samples=[r for r in rows if r['kind']=='recovery_sample'];assert any(1<=r['state']<=4 for r in samples)
  final=samples[-1];assert (final['cache'],final['state'],final['player'],final['attempts'])==(15,0,7,0)
  assert complete[0]['recovery_requests']==1
  record.update(recovery_requests=1,observed_busy=True,returned_ready=True)
 return record
program=read(RUN/'programming/programming.json');assert program['program_sram_command_succeeded'] and program['process_exit']==0 and not program['flash_written']
expected='c155437a50af13ca4b95864a3b41c498b36bfe2a147600ddd595633d6dd32642';assert program['bit_sha256']==expected
assert sha(a.bit)==expected
console=(RUN/'programming/download.console.log').read_text(encoding='utf-8-sig');assert 'BW_SRAM_FULL36_COMMAND_COMPLETED' in console and 'Chip validation success: EG4S20BG256' in console
probes=[]
for name in ('probe01','probe_after_recovery'):
 p=analyze(RUN/name,0x26101736);assert p['capture_complete'] and not p['errors'] and p['self_reported_id_matches_expected'];healthy(p['values'])
 assert p['values']['STATUS']==7 and p['values']['IDLOW']==0x00020001 and p['values']['IDHIGH']==0x00040003
 probes.append(dict(name=name,values=p['values'],rx_sha256=p['rx_sha256'],queries=len(p['transactions'])))
tests=[trace(RUN/'playback01',8),trace(RUN/'playback100',100),trace(RUN/'recovery01',recovery=True)]
result=dict(schema=1,serial_and_control_checks_passed=True,firmware_id='26101736',bit_sha256=expected,manual_commits=sum(t.get('manual_commits',0) for t in tests),auto_commits=sum(t.get('auto_commits',0) for t in tests),recovery_requests=1,tests=tests,probes=probes,physical_display_verified=False,physical_audio_verified=False,physical_buttons_verified=False,hardware_full_acceptance=False,hd_timing_accepted=False,github_uploaded=False)
(RUN/'board.audit.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('RAW UART VERIFIED:108 manual/'+str(result['auto_commits'])+' auto/1 recovery; screen/audio/buttons pending')
