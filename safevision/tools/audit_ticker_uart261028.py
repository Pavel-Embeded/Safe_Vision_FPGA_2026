"""Recheck captured UART bytes and the complete ticker board campaign."""
from pathlib import Path
import argparse,hashlib,json,math,re

FRAME=re.compile(rb'\$(C:ACK=([0-9A-F]{2}),([0-9A-F]{8}))\*([0-9A-F]{2})\r\n')
CRITICAL=('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW')
COUNTERS=('EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')
def require(ok,message):
 if not ok:raise ValueError(message)
def xor(data):
 n=0
 for b in data:n^=b
 return n
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def audit(folder,minimum_seconds=7200,transitions=100,recoveries=10):
 events=[json.loads(s)for s in(folder/'trace.jsonl').read_text('utf-8-sig').splitlines()if s]
 require(events and events[0]['kind']=='opened'and events[-1]['kind']=='closed'and events[-1]['exit_code']==0,'missing normal serial open/close')
 require(all(e['kind']not in('error','failure_restore_attempted','failure_restore_error')for e in events),'serial campaign contains a failure')
 require(events[0]['baud']==115200 and events[0]['expected_id']=='26102801','unexpected serial profile')
 require(all(a['elapsed_ms']<=b['elapsed_ms']for a,b in zip(events,events[1:])),'nonmonotonic capture clock')
 raw=(folder/'rx.bin').read_bytes()
 require(raw==b''.join(bytes.fromhex(e['hex'])for e in events if e['kind']=='rx'),'raw serial bytes differ from trace')
 for e in events:
  if e['kind']=='rx':require(e['text'].encode('ascii')==bytes.fromhex(e['hex']),'RX text differs from raw bytes')
 sent=[e for e in events if e['kind']=='tx'];replies=[e for e in events if e['kind']=='ack'];frames=list(FRAME.finditer(raw))
 require(len(sent)==len(replies)==len(frames)>0,'transmit/ACK/raw inventory differs')
 require(sent[0]['body']=='B:DIAG=0'and replies[0]['value']==0x26102801,'firmware not identified before writes')
 for tx,ack,match in zip(sent,replies,frames):
  body=tx['body'].encode('ascii');packet=b'$'+body+('*%02X\r\n'%xor(body)).encode('ascii')
  require(bytes.fromhex(tx['hex'])==packet and tx['body']==ack['body'],'TX frame/body mismatch')
  require(match[0]==(ack['frame']+'\r\n').encode('ascii'),'ACK event differs from received frame')
  require(xor(match[1])==int(match[4],16),'ACK XOR mismatch')
  require(int(match[2],16)==ack['code']==0 and int(match[3],16)==ack['value'],'ACK status/value mismatch')
  require(0<=ack['elapsed_ms']-tx['elapsed_ms']<=2100,'ACK outside transaction timeout')
  if tx['body']=='B:DIAG=101':require(ack['value']>>12==0x544B1 and(ack['value']&4095)<1024,'invalid ticker signature/position')
 # Cross-check derived events against the actual preceding ACKs. A rewritten
 # summary cannot fabricate slot commits, health, or recovery observations.
 live={};next_request=None;recover_request=None;recovery_busy=False;cache_cleared=False
 for e in events:
  kind=e['kind']
  if kind=='tx'and e['body']=='C:NEXT=1':next_request=(e['elapsed_ms'],live.get('B:SLOT?'),live.get('B:GEN?'))
  if kind=='tx'and e['body']=='C:RECOVER=1':recover_request=e['elapsed_ms'];recovery_busy=False;cache_cleared=False
  if kind=='ack':
   live[e['body']]=e['value']
   if recover_request is not None:
    if e['body']=='B:RECOVERY?'and 0<e['value']<5:recovery_busy=True
    if e['body']=='B:CACHE?'and e['value']!=15:cache_cleared=True
  if kind=='health':require(all(live.get('B:'+q+'?')==v for q,v in e['values'].items()),'health receipt differs from ACK values')
  if kind=='monitor':require(all(live.get('B:'+q+'?')==v for q,v in e['values'].items()),'monitor receipt differs from ACK values')
  if kind=='transition':
   require(next_request is not None and next_request[1]is not None and next_request[2]is not None,'transition has no initial slot/generation')
   request,slot,generation=next_request
   require(request==e['requested_ms']and e['slot']==(slot+1)%4 and e['generation']==(generation+1)%256,'NEXT did not commit exactly once')
   require((e['slot'],e['generation'],e['latency_ms'])==(live.get('B:SLOT?'),live.get('B:GEN?'),live.get('B:LATENCY?')),'transition receipt differs from raw replies')
   next_request=None
  if kind=='recovery':
   require(recover_request is not None and recover_request==e['request_ms']and recovery_busy and cache_cleared,'recovery lacks actual busy/cache-clear replies')
   require(live.get('B:RECOVERY?')==0 and live.get('B:CACHE?')==15 and live.get('B:STATUS?')==7,'recovery did not restore READY')
   recover_request=None
 health=[e for e in events if e['kind']=='health'];require(health,'no health samples')
 for e in health:
  v=e['values'];require(v['CACHE']==15 and all(v[q]==0 for q in CRITICAL),'critical health fault')
  require(v['FAULT']==0 or(v['FAULT']==7 and v['WAVFALLBACK']>0),'unexpected media fault')
 tick=[e for e in events if e['kind']=='ticker'];rates=[e for e in events if e['kind']=='ticker_rate']
 tickacks=[e for e in replies if e['body']=='B:DIAG=101']
 require(len(tick)==len(tickacks)and len(rates)==len(tick)-1 and len(tick)>2,'ticker observation inventory mismatch')
 for sample,ack in zip(tick,tickacks):
  require(sample['position']==ack['value']&4095 and sample['period_pixels']==1024,'ticker sample differs from ACK')
 for before,after,rate in zip(tick,tick[1:],rates):
  dt=after['sample_ms']-before['sample_ms'];expected=math.floor(dt*.0299823633)%1024
  actual=(after['position']-before['position'])%1024;error=(actual-expected+512)%1024-512
  require(dt>0 and abs(error)<=4,'ticker cadence/reset failure')
  require((rate['interval_ms'],rate['expected_pixels'],rate['actual_pixels'],rate['position_error'])==(dt,expected,actual,error),'ticker rate receipt differs')
 moves=[e for e in events if e['kind']=='transition'];restores=[e for e in events if e['kind']=='recovery'];monitor=[e for e in events if e['kind']=='monitor'];complete=[e for e in events if e['kind']=='complete']
 require(len(moves)==transitions and len([e for e in sent if e['body']=='C:NEXT=1'])==transitions,'transition count differs')
 require([e['index']for e in moves]==list(range(transitions)),'transition index differs')
 for i,e in enumerate(moves):
  require(e['observed_ms']>=e['requested_ms']and 0<=e['latency_ms']<65535,'invalid/canceled transition latency')
  if i:require(e['slot']==(moves[i-1]['slot']+1)%4 and e['generation']==(moves[i-1]['generation']+1)%256,'transition did not commit once')
 require(len(restores)==recoveries and len([e for e in sent if e['body']=='C:RECOVER=1'])==recoveries,'recovery count differs')
 for i,e in enumerate(restores):require(e['index']==i and e['busy']and e['cache_clear']and 0<e['duration_ms']<=30000 and e['duration_ms']==e['completed_ms']-e['request_ms'],'incomplete recovery')
 require(monitor and len(complete)==1,'missing continuous monitor/completion')
 for i,e in enumerate(monitor):require(e['index']==i and e['values']['STATUS']==7 and all(e['values'][q]==0 for q in COUNTERS),'monitor health failed')
 done=complete[0];require(done['continuous_monitor_ms']>=minimum_seconds*1000 and monitor[-1]['duration_ms']>=minimum_seconds*1000-10000,'continuous run too short')
 require(done['defaults_restored']and done['manual_commits']==transitions and done['recoveries']==recoveries,'completion inventory/defaults differ')
 values=sorted(e['latency_ms']for e in moves);count=len(values)
 statistics=dict(count=count,minimum_ms=values[0],median_ms=(values[(count-1)//2]+values[count//2])/2,p95_ms=values[math.ceil(.95*count)-1],maximum_ms=values[-1])
 require(done['latency']==statistics,'latency statistics differ from individual transitions')
 saved=json.loads((folder/'summary.json').read_text('utf-8-sig'));require(saved['accepted']and saved['latency']==statistics and saved['continuous_monitor_ms']==done['continuous_monitor_ms'],'summary differs from raw campaign')
 return dict(accepted=True,firmware_id='26102801',ack_count=len(replies),manual_commits=transitions,recoveries=recoveries,continuous_monitor_ms=done['continuous_monitor_ms'],ticker_samples=len(tick),latency=statistics,trace_sha256=sha(folder/'trace.jsonl'),rx_sha256=sha(folder/'rx.bin'),physical_display_verified=False,scope='Recorded UART byte replay; no new hardware interaction')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--folder',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=audit(a.folder)
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('TICKER UART AUDIT '+('PASS'if r['accepted']else'FAILED: '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
