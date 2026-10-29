
import re

PREFIX='sink/u_bridge/writer/'

def check(text):
 expected={PREFIX+stem+'['+str(i)+']'for stem in ('crc_pair_q','wr_data_r')for i in range(32)}|{PREFIX+'sample_mismatch'}
 starts=list(re.finditer(r'(?m)^\s{2}(EG_(?:PHY|LOGIC)_[A-Z0-9_]+)\s*#\(',text))
 drivers={name:[]for name in expected}
 for i,m in enumerate(starts):
  block=text[m.start():starts[i+1].start()if i+1<len(starts)else len(text)]
  boundary=re.search(r'\)\s*(\\?[^\s()]+)\s*\(\s*\n',block)
  if not boundary:continue
  params=block[:boundary.start()];ports=block[boundary.end():]
  q=re.search(r'\.q\(\s*([^)]*)\)',ports,re.S)
  if not q:continue
  parts=[]
  for part in q[1].strip().strip('{}').split(','):


   net=re.sub(r'\s+(?=\[\d+(?::\d+)?\])','',part.strip()).lstrip('\\').strip()
   span=re.fullmatch(r'(.*)\[(\d+):(\d+)\]',net)
   if span:
    hi,lo=int(span[2]),int(span[3]);step=-1 if hi>=lo else 1
    parts.extend(span[1]+'['+str(bit)+']'for bit in range(hi,lo+step,step))
   else:parts.append(net)
  for position,net in enumerate(parts):
   if net not in expected:continue
   if m[1]not in ('EG_PHY_LSLICE','EG_PHY_MSLICE')or not re.search(r'\.DFFMODE\("FF"\)',params):raise ValueError('sample Q is not a physical FF output: '+net)
   if not re.search(r'\.clk\(\s*\\?[A-Za-z_][^\s)]+',ports):raise ValueError('sample FF clock is absent/tied: '+net)
   drivers[net].append((boundary[1],len(parts)-1-position))
 bad={net:len(rows)for net,rows in drivers.items()if len(rows)!=1}
 if bad:raise ValueError('sample physical Q drivers missing/duplicated: '+repr(bad))
 bindings=[rows[0]for rows in drivers.values()]
 if len(set(bindings))!=65:raise ValueError('source/bus/fault physical FF outputs aliased')
 return dict(accepted=True,source_bits=32,bus_bits=32,fault_bits=1,independent_physical_q_pins=65,packed_cell_names_may_change=True)
