"""Test UART evidence checks with synthetic fixtures; never a board result."""
import copy,json,tempfile,unittest
from pathlib import Path
from audit_ticker_uart261028 import audit,xor,DEFAULTS,CRITICAL,COUNTERS

def fixture():
 events=[];now=0;live={};ticks=[];moves=[]
 def emit(kind,**fields):
  events.append(dict(kind=kind,elapsed_ms=now,**fields))
 def transaction(body,value):
  nonlocal now
  now+=2;emit('tx',body=body,hex=(b'$'+body.encode()+('*%02X\r\n'%xor(body.encode())).encode()).hex())
  packet='C:ACK=00,%08X'%value;frame='$'+packet+('*%02X'%xor(packet.encode()))
  now+=2;emit('rx',hex=(frame+'\r\n').encode().hex(),text=frame+'\r\n')
  emit('ack',body=body,code=0,value=value,frame=frame);live[body]=value
  return now-2
 def health():
  values={'CACHE':15,'FAULT':0,'LEVEL':0,'WAVFALLBACK':0,**{q:0 for q in CRITICAL}}
  for q,v in values.items():transaction('B:'+q+'?',v)
  emit('health',values=values)
 def ticker():
  # ACK is four ms after the initial fixture time. The phase is measured
  # from that same monotonic clock, including across the modulo768 wrap.
  t=now+4;position=int(t*.0299823633)%1024
  transaction('B:DIAG=101',0x544B1000|position)
  if ticks:
   before=ticks[-1];dt=t-before['sample_ms'];expected=int(dt*.0299823633)%1024
   actual=(position-before['position'])%1024
   emit('ticker_rate',interval_ms=dt,expected_pixels=expected,actual_pixels=actual,position_error=(actual-expected+512)%1024-512)
  sample=dict(position=position,sample_ms=t,period_pixels=1024);ticks.append(sample);emit('ticker',**sample)
 emit('opened',baud=115200,expected_id='26102801')
 transaction('B:DIAG=0',0x26102801);health();ticker()
 transaction('C:AUTO=0',0);transaction('B:SLOT?',0);transaction('B:GEN?',254)
 for index in range(2):
  request=transaction('C:NEXT=1',1);now+=1000
  transaction('B:SLOT?',index+1);transaction('B:GEN?',(255+index)%256);transaction('B:LATENCY?',20+index)
  movement=dict(index=index,requested_ms=request,observed_ms=now,slot=index+1,generation=(255+index)%256,latency_ms=20+index)
  emit('transition',**movement);moves.append(movement);health();ticker()
 for index in range(2):
  request=transaction('C:RECOVER=1',1)
  transaction('B:RECOVERY?',1);transaction('B:CACHE?',0);now+=200
  transaction('B:RECOVERY?',0);transaction('B:CACHE?',15);transaction('B:STATUS?',7)
  complete=now;health();ticker()
  emit('recovery',index=index,request_ms=request,completed_ms=complete,duration_ms=complete-request,busy=True,cache_clear=True)
 for q,v in DEFAULTS.items():transaction(q+'='+str(v),v)
 for q,v in DEFAULTS.items():transaction(q+'?',v)
 emit('defaults',values=dict(DEFAULTS));start=now;emit('monitor_started',start_ms=start)
 # Twelve samples extend beyond a full scroll wrap and exercise continuous
 # observation plus generation255->0. No simulated seconds are wall time.
 for index in range(12):
  now=start+5000*(index+1);health();ticker()
  values={'STATUS':7,'SLOT':(3+index)%4,'GEN':index+1,**{q:0 for q in COUNTERS}}
  for q,v in values.items():transaction('B:'+q+'?',v)
  emit('monitor',index=index,values=values,duration_ms=now-start)
 stats=dict(count=2,minimum_ms=20,median_ms=20.5,p95_ms=21,maximum_ms=21)
 duration=now-start
 emit('complete',continuous_monitor_ms=duration,defaults_restored=True,manual_commits=2,recoveries=2,latency=stats)
 emit('closed',exit_code=0)
 summary=dict(accepted=True,latency=stats,continuous_monitor_ms=duration)
 return events,summary

class UartControls(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='sv-ticker-uart-');self.root=Path(self.temp.name)
  self.events,self.summary=fixture()
 def tearDown(self):self.temp.cleanup()
 def check(self,events=None,summary=None,raw=None):
  e=self.events if events is None else events;s=self.summary if summary is None else summary
  (self.root/'trace.jsonl').write_text(''.join(json.dumps(v)+'\n'for v in e),'utf-8')
  (self.root/'rx.bin').write_bytes(b''.join(bytes.fromhex(v['hex'])for v in e if v['kind']=='rx')if raw is None else raw)
  (self.root/'summary.json').write_text(json.dumps(s),'utf-8')
  return audit(self.root,minimum_seconds=30,transitions=2,recoveries=2)
 def mutate(self,kind,field,value):
  rows=copy.deepcopy(self.events);next(v for v in rows if v['kind']==kind)[field]=value;return rows
 def reply(self,rows,body,old_value,new_value):
  for index,e in enumerate(rows):
   if e['kind']!='ack'or e['body']!=body or e['value']!=old_value:continue
   packet='C:ACK=00,%08X'%new_value;frame='$'+packet+('*%02X'%xor(packet.encode()))
   self.assertEqual(rows[index-1]['kind'],'rx')
   rows[index-1].update(hex=(frame+'\r\n').encode().hex(),text=frame+'\r\n')
   e.update(frame=frame,value=new_value)
 def test_round_trip(self):
  result=self.check();self.assertTrue(result['accepted']);self.assertFalse(result['physical_display_verified']);self.assertEqual(result['period_pixels'],1024)
 def test_unclosed_capture(self):
  with self.assertRaisesRegex(ValueError,'open/close'):self.check(self.events[:-1])
 def test_raw_rewrite(self):
  with self.assertRaisesRegex(ValueError,'raw serial'):self.check(raw=b'edited')
 def test_rewritten_transition(self):
  with self.assertRaisesRegex(ValueError,'commit exactly once'):self.check(self.mutate('transition','generation',42))
 def test_recovery_without_busy(self):
  rows=copy.deepcopy(self.events);self.reply(rows,'B:RECOVERY?',1,0)
  with self.assertRaisesRegex(ValueError,'busy/cache-clear'):self.check(rows)
 def test_recovery_without_cleared_cache(self):
  rows=copy.deepcopy(self.events);self.reply(rows,'B:CACHE?',0,15)
  with self.assertRaisesRegex(ValueError,'busy/cache-clear'):self.check(rows)
 def test_stalled_phase(self):
  rows=copy.deepcopy(self.events);samples=[v for v in rows if v['kind']=='ticker'];samples[-1]['position']=samples[-2]['position']
  with self.assertRaisesRegex(ValueError,'sample differs'):self.check(rows)
 def test_detached_ticker_clock(self):
  with self.assertRaisesRegex(ValueError,'detached'):self.check(self.mutate('ticker','sample_ms',0))
 def test_fabricated_defaults(self):
  rows=copy.deepcopy(self.events);next(v for v in rows if v['kind']=='defaults')['values']['C:VOL']=100
  with self.assertRaisesRegex(ValueError,'default configuration'):self.check(rows)
 def test_default_readback_wrong(self):
  rows=copy.deepcopy(self.events);self.reply(rows,'C:VOL?',70,100)
  with self.assertRaisesRegex(ValueError,'actual write and readback'):self.check(rows)
 def test_omitted_defaults(self):
  with self.assertRaisesRegex(ValueError,'default readback'):self.check([v for v in self.events if v['kind']!='defaults'])
 def test_shortened_monitor(self):
  with self.assertRaisesRegex(ValueError,'duration differs|too short'):self.check(self.mutate('monitor','duration_ms',0))
 def test_summary_invented(self):
  summary=copy.deepcopy(self.summary);summary['continuous_monitor_ms']+=1000
  with self.assertRaisesRegex(ValueError,'summary differs'):self.check(summary=summary)
 def test_duration_offset_invented(self):
  rows=copy.deepcopy(self.events);summary=copy.deepcopy(self.summary)
  for e in rows:
   if e['kind']=='monitor':e['duration_ms']+=30000
   if e['kind']=='complete':e['continuous_monitor_ms']+=30000
  summary['continuous_monitor_ms']+=30000
  with self.assertRaisesRegex(ValueError,'duration differs'):self.check(rows,summary)
 def test_monitor_origin_omitted(self):
  with self.assertRaisesRegex(ValueError,'monitor origin'):self.check([v for v in self.events if v['kind']!='monitor_started'])
 def test_automatic_slideshow_stalled(self):
  rows=copy.deepcopy(self.events)
  for value in range(1,13):self.reply(rows,'B:GEN?',value,0)
  for e in rows:
   if e['kind']=='monitor':e['values']['GEN']=0
  with self.assertRaisesRegex(ValueError,'slideshow generation stalled'):self.check(rows)
 def test_malformed_ack_ignored(self):
  rows=copy.deepcopy(self.events);rx=next(v for v in rows if v['kind']=='rx')
  rx['text']+='$C:ACK=00,NOTHEX*00\r\n';rx['hex']=rx['text'].encode().hex()
  with self.assertRaisesRegex(ValueError,'malformed or incomplete'):self.check(rows)
 def test_health_rewrite(self):
  rows=copy.deepcopy(self.events);next(v for v in rows if v['kind']=='health')['values']['INTEGRITY']=1
  with self.assertRaisesRegex(ValueError,'health receipt'):self.check(rows)

if __name__=='__main__':unittest.main()
