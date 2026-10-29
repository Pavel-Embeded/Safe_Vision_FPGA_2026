"""Recheck captured UART bytes and the complete ticker board campaign."""
from pathlib import Path
import argparse,hashlib,json,math,re

FRAME=re.compile(rb'\$(C:ACK=([0-9A-F]{2}),([0-9A-F]{8}))\*([0-9A-F]{2})\r\n')
CRITICAL=('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW')
COUNTERS=('EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')
DEFAULTS={'A:BRTPC':80,'A:CONTRAST':128,'A:ALPHA':160,'A:SCALER':0,'A:SCALESEL':0,'A:FADE':1,'C:VOL':70,'C:PERIOD':5,'C:FIELD':0,'C:MENU':0,'C:AUTO':1}
def require(ok,message):
 if not ok:raise ValueError(message)
def xor(data):
 n=0
 for b in data:n^=b
 return n
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def cadence_window(before_start,before_end,after_start,after_end,before_position,after_position):
 # Sampling instants are contained in the two raw TX/ACK transactions.
 require(0<=before_start<=before_end<=after_start<=after_end and after_end>before_end,'detached or overlapping ticker transaction window')
 low_ms=after_start-before_end;high_ms=after_end-before_start
 low=max(0,math.floor(low_ms*.0299823633)-4);high=math.ceil(high_ms*.0299823633)+4
 actual=(after_position-before_position)%1024
 observed=actual+1024*math.ceil((low-actual)/1024)
 require(low<=observed<=high,'ticker cadence/reset failure')
 dt=after_end-before_end;expected=math.floor(dt*.0299823633)%1024
 return dict(interval_ms=dt,expected_pixels=expected,actual_pixels=actual,position_error=(actual-expected+512)%1024-512,interval_min_ms=low_ms,interval_max_ms=high_ms,advance_min_pixels=low,advance_max_pixels=high,observed_advance_pixels=observed)

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
 require(raw.count(b'$C:ACK=')==len(frames),'malformed or incomplete raw ACK frame')
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
 live={};next_request=None;recover_request=None;recovery_busy=False;cache_cleared=False;default_time=None
 for e in events:
  kind=e['kind']
  if kind=='tx'and default_time is not None:require(not(e['body'].startswith(('A:','C:'))and'='in e['body']),'configuration changed after default readback')
  if kind=='tx'and e['body']=='C:NEXT=1':next_request=(e['elapsed_ms'],live.get('B:SLOT?'),live.get('B:GEN?'))
  if kind=='tx'and e['body']=='C:RECOVER=1':recover_request=e['elapsed_ms'];recovery_busy=False;cache_cleared=False
  if kind=='ack':
   live[e['body']]=e['value']
   if recover_request is not None:
    if e['body']=='B:RECOVERY?'and 0<e['value']<5:recovery_busy=True
    if e['body']=='B:CACHE?'and e['value']!=15:cache_cleared=True
  if kind=='health':require(all(live.get('B:'+q+'?')==v for q,v in e['values'].items()),'health receipt differs from ACK values')
  if kind=='monitor':require(all(live.get('B:'+q+'?')==v for q,v in e['values'].items()),'monitor receipt differs from ACK values')
  if kind=='defaults':
   require(default_time is None and e['values']==DEFAULTS,'default configuration receipt differs')
   require(all(live.get(q+'?')==value and live.get(q+'='+str(value))is not None for q,value in DEFAULTS.items()),'defaults lack actual write and readback replies')
   default_time=e['elapsed_ms']
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
 ticktx=[e for e in sent if e['body']=='B:DIAG=101']
 require(len(tick)==len(tickacks)and len(rates)==len(tick)-1 and len(tick)>2,'ticker observation inventory mismatch')
 for sample,tx,ack in zip(tick,ticktx,tickacks):
  require(sample['position']==ack['value']&4095 and sample['period_pixels']==1024,'ticker sample differs from ACK')
  require(sample['sample_ms']==sample['transaction_end_ms']==ack['elapsed_ms']and sample['transaction_start_ms']==tx['elapsed_ms']and sample['elapsed_ms']>=sample['sample_ms'],'ticker time is detached from its raw transaction')
 for before,after,rate in zip(tick,tick[1:],rates):
  expected=cadence_window(before['transaction_start_ms'],before['transaction_end_ms'],after['transaction_start_ms'],after['transaction_end_ms'],before['position'],after['position'])
  require(all(rate[k]==v for k,v in expected.items()),'ticker rate receipt differs')
 moves=[e for e in events if e['kind']=='transition'];restores=[e for e in events if e['kind']=='recovery'];monitor=[e for e in events if e['kind']=='monitor'];complete=[e for e in events if e['kind']=='complete'];starts=[e for e in events if e['kind']=='monitor_started']
 require(len(moves)==transitions and len([e for e in sent if e['body']=='C:NEXT=1'])==transitions,'transition count differs')
 require([e['index']for e in moves]==list(range(transitions)),'transition index differs')
 for i,e in enumerate(moves):
  require(e['observed_ms']>=e['requested_ms']and 0<=e['latency_ms']<65535,'invalid/canceled transition latency')
  if i:require(e['slot']==(moves[i-1]['slot']+1)%4 and e['generation']==(moves[i-1]['generation']+1)%256,'transition did not commit once')
 require(len(restores)==recoveries and len([e for e in sent if e['body']=='C:RECOVER=1'])==recoveries,'recovery count differs')
 for i,e in enumerate(restores):require(e['index']==i and e['busy']and e['cache_clear']and 0<e['duration_ms']<=30000 and e['duration_ms']==e['completed_ms']-e['request_ms'],'incomplete recovery')
 require(monitor and len(complete)==1 and default_time is not None and default_time<monitor[0]['elapsed_ms'],'missing continuous monitor/completion/default readback')
 require(len(starts)==1,'missing unique continuous-monitor origin')
 origin=starts[0]['start_ms']
 require(default_time<=origin and 0<=starts[0]['elapsed_ms']-origin<=100,'monitor origin differs from capture clock')
 require(0<=monitor[0]['elapsed_ms']-origin<=15000,'unobserved gap at monitor start')
 generation=None;generation_time=None
 for i,e in enumerate(monitor):require(e['index']==i and e['values']['STATUS']==7 and all(e['values'][q]==0 for q in COUNTERS),'monitor health failed')
 for e in monitor:
  require(abs(e['duration_ms']-(e['elapsed_ms']-origin))<=100,'monitor duration differs from capture clock')
  if generation is None:generation=e['values']['GEN'];generation_time=e['elapsed_ms']
  elif e['elapsed_ms']-generation_time>=30000:
   require(e['values']['GEN']!=generation,'automatic slideshow generation stalled for30seconds')
   generation=e['values']['GEN'];generation_time=e['elapsed_ms']
 require(len(monitor)>=max(1,minimum_seconds//10),'too few continuous health observations')
 for before,after in zip(monitor,monitor[1:]):
  require(0<after['duration_ms']-before['duration_ms']<=15000,'unobserved gap in continuous monitoring')
  require(abs((after['duration_ms']-before['duration_ms'])-(after['elapsed_ms']-before['elapsed_ms']))<=10,'monitor duration differs from capture clock')
 done=complete[0];require(abs(done['continuous_monitor_ms']-(done['elapsed_ms']-origin))<=100,'completion duration differs from capture clock')
 require(0<=done['elapsed_ms']-monitor[-1]['elapsed_ms']<=15000,'unobserved gap at monitor end')
 require(done['continuous_monitor_ms']>=minimum_seconds*1000 and monitor[-1]['duration_ms']>=minimum_seconds*1000-10000,'continuous run too short')
 require(done['defaults_restored']and done['manual_commits']==transitions and done['recoveries']==recoveries,'completion inventory/defaults differ')
 values=sorted(e['latency_ms']for e in moves);count=len(values)
 statistics=dict(count=count,minimum_ms=values[0],median_ms=(values[(count-1)//2]+values[count//2])/2,p95_ms=values[math.ceil(.95*count)-1],maximum_ms=values[-1])
 require(done['latency']==statistics,'latency statistics differ from individual transitions')
 saved=json.loads((folder/'summary.json').read_text('utf-8-sig'));require(saved['accepted']and saved['latency']==statistics and saved['continuous_monitor_ms']==done['continuous_monitor_ms'],'summary differs from raw campaign')
 return dict(accepted=True,firmware_id='26102801',period_pixels=1024,ack_count=len(replies),manual_commits=transitions,recoveries=recoveries,continuous_monitor_ms=done['continuous_monitor_ms'],ticker_samples=len(tick),latency=statistics,trace_sha256=sha(folder/'trace.jsonl'),rx_sha256=sha(folder/'rx.bin'),physical_display_verified=False,scope='Recorded UART byte replay; no new hardware interaction')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--folder',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=audit(a.folder)
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('TICKER UART AUDIT '+('PASS'if r['accepted']else'FAILED: '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
