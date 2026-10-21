"""Audit actual configuration UART bytes and round-trip restoration."""
import hashlib,json,re,sys
from pathlib import Path
folder=Path(sys.argv[1]);rows=[json.loads(s) for s in (folder/'trace.jsonl').read_text(encoding='utf-8-sig').splitlines()]
raw=(folder/'rx.bin').read_bytes();assert raw==b''.join(bytes.fromhex(r['hex']) for r in rows if r['kind']=='rx')
frame=re.compile(rb'\$([^$\r\n]*)\*([0-9A-F]{2})\r\n');ack=re.compile(rb'C:ACK=([0-9A-F]{2}),([0-9A-F]{8})')
def parse(data):
 result=[]
 for m in frame.finditer(data):
  crc=0
  for b in m[1]:crc^=b
  assert crc==int(m[2],16);result.append((m[1],m))
 return result
pending=None;response=b'';acks=[];txbytes=0;cases=[]
for row in rows:
 if row['kind']=='tx':
  assert pending is None;tx=bytes.fromhex(row['hex']);p=parse(tx);assert len(p)==1 and p[0][0].decode()==row['body'] and p[0][1].span()==(0,len(tx))
  pending=row;response=b'';txbytes+=len(tx)
 elif row['kind']=='rx' and pending is not None:response+=bytes.fromhex(row['hex'])
 elif row['kind']=='ack':
  assert pending and pending['body']==row['body'] and row['elapsed_ms']-pending['elapsed_ms']<2000
  replies=[m for b,m in parse(response) if ack.fullmatch(b)];assert len(replies)==1
  c,v=(int(x,16) for x in ack.fullmatch(replies[0][1]).groups());assert c==row['code']==0 and v==row['value'];acks.append(row);pending=None
 elif row['kind']=='configuration_case':
  last=next(r for r in reversed(acks) if r['body']==row['name']+'?');signed=last['value']-(1<<32) if last['value']>=(1<<31) else last['value']
  assert signed==row['actual']==row['requested'];cases.append((row['name'],row['requested']))
 elif row['kind']=='health':
  v=row['values'];assert v['CACHE']==15 and all(v[k]==0 for k in ('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW'))
  assert v['FAULT']==0 or(v['FAULT']==7 and v['WAVFALLBACK']>0)
assert pending is None and rows[-1]['kind']=='closed' and rows[-1]['exit_code']==0
assert not any(r['kind']=='error' for r in rows)
assert sum(bool(ack.fullmatch(b)) for b,m in parse(raw))==len(acks)
assert acks[0]['body']=='B:DIAG=0' and acks[0]['value']==0x26101736
expected=[('A:BRIGHT',-64),('A:BRIGHT',64),('A:CONTRAST',64),('A:CONTRAST',192),('A:ALPHA',0),('A:ALPHA',128),('A:ALPHA',255),('A:SCALER',0),('A:SCALER',1),('A:SCALE',0),('A:SCALE',1),('A:FADE',0),('A:FADE',1),('C:VOL',0),('C:VOL',50),('C:VOL',100),('C:PERIOD',2),('C:PERIOD',5),('C:PERIOD',10),('C:PERIOD',30)]
assert cases==expected
for name in ('C:AUTO','C:PERIOD','A:BRIGHT','A:CONTRAST','A:ALPHA','A:SCALER','A:SCALE','A:FADE','C:VOL'):
 values=[r['value'] for r in acks if r['body']==name+'?'];assert values[0]==values[-1],name
complete=[r for r in rows if r['kind']=='complete'];assert len(complete)==1 and complete[0]['settings_restored']
result=dict(serial_configuration_checks_passed=True,configuration_cases=len(cases),ack_count=len(acks),tx_bytes=txbytes,rx_bytes=len(raw),rx_sha256=hashlib.sha256(raw).hexdigest(),settings_restoration_independently_checked=True,firmware_self_reported_id='26101736',physical_display_verified=False,physical_audio_verified=False,hardware_full_acceptance=False,github_uploaded=False)
(folder/'configuration.audit.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('CONFIGURATION RAW AUDIT PASS:20cases,nine settings restored,'+str(len(acks))+' matched ACKs')
