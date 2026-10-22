"""Check independent board-material pin contract against ADC and routed pads."""
import argparse,json,re
from pathlib import Path
from v3_sources import ROOT,FLOW

def adc_pins(text):
 rows={}
 for line in text.splitlines():
  if not line.strip() or line.lstrip().startswith('#'):continue
  m=re.fullmatch(r'\s*set_pin_assignment\s+\{\s*(\S+)\s*\}\s+\{([^}]+)\}\s*',line)
  if not m:raise ValueError('unparsed ADC statement')
  if m[1] in rows:raise ValueError('duplicate ADC port')
  fields={k:v for k,v in re.findall(r'(\w+)\s*=\s*(\w+)\s*;',m[2])}
  rows[m[1]]=fields
 return rows

def check(root,area=None):
 ref=json.loads((root/FLOW/'board_reference.json').read_text(encoding='utf-8'))
 pins=ref['ports'];actual=adc_pins((root/FLOW/'v3_board.adc').read_text(encoding='utf-8-sig'))
 # Independent physical labels from HX4S20 manual2410 printed p19.
 # Checking ADC against a copied reference alone missed a shared KEY3/4 swap.
 # Keep the physical labels anchored even if both editable tables agree.
 key_contract=(('KEY1','A2','rst_n'),('KEY2','B2','btn_next'),
               ('KEY3','B1','btn_auto'),('KEY4','C1','btn_emergency'))
 expected=[dict(button=label,ball=ball,logical_port=port,active_level=0)for label,ball,port in key_contract]
 if ref.get('key_function_contract')!=expected:raise ValueError('physical KEY1..4 function contract differs from manual2410 p19')
 for label,ball,port in key_contract:
  if pins.get(port,{}).get('LOCATION')!=ball:raise ValueError(label+' reference ball differs from manual2410 p19: '+port)
  if actual.get(port,{}).get('LOCATION')!=ball:raise ValueError(label+' ADC ball differs from manual2410 p19: '+port)
  if actual[port].get('PULLTYPE')!='PULLUP':raise ValueError(label+' must retain its active-low pull-up')
 if set(actual)!=set(pins):raise ValueError('ADC port inventory differs from reviewed board contract')
 locations=[]
 for name,row in pins.items():
  for key in ('LOCATION','IOSTANDARD','PULLTYPE'):
   if actual[name].get(key)!=row[key]:raise ValueError('board pin/property mismatch: '+name+'/'+key)
  if 'DRIVESTRENGTH' in row and actual[name].get('DRIVESTRENGTH')!=row['DRIVESTRENGTH']:raise ValueError('board drive mismatch: '+name)
  locations.append(row['LOCATION'])
 negatives={p['negative_ball'] for p in ref['differential_pairs']}
 if len(set(locations))!=21 or len(negatives)!=4 or set(locations)&negatives:raise ValueError('duplicate/reserved differential pad conflict')
 sdc=(root/FLOW/'v3_board.sdc').read_text(encoding='utf-8-sig')
 if not re.search(r'^create_clock\s+-name\s+board_clk\s+-period\s+20(?:\.0+)?\s+-waveform\s+\{0 10\}\s+\[get_ports\s+\{clk\}\]\s*$',sdc,re.M):raise ValueError('board oscillator constraint differs from 50MHz R7')
 result={'accepted':True,'logical_ports':21,'physical_pads':25,'adc_checked':True,'physical_pad_table_checked':False,'hardware_verified':False,'physical_key_contract':expected,'key_contract_source':'HX4S20 manual2410 printed p19; KEY3=B1 and KEY4=C1'}
 if area is not None:
  if 'Device: EG4S20BG256' not in area:raise ValueError('wrong routed device')
  # Internal SDRAM Sxx pads are package-internal and are not user BGA balls.
  rows=[]
  for m in re.finditer(r'^\s*(\S+)\s+(INPUT|OUTPUT|INOUT)\s+([A-RT]\d+)\s+(\w+)\s+(\w+)\s+(\d+|NA|N/A|-)\s+(\w+)\s+',area,re.M):
   rows.append({'name':m[1],'direction':m[2],'ball':m[3],'standard':m[4]})
  if len(rows)!=25:raise ValueError('missing/extra/ambiguous routed physical user pads: '+str(len(rows)))
  by_ball={r['ball']:r for r in rows}
  if len(by_ball)!=25 or set(by_ball)!=set(locations)|negatives:raise ValueError('routed BGA pin set mismatch')
  for name,pin in pins.items():
   row=by_ball[pin['LOCATION']]
   if row['name']!=name or row['standard']!=pin['IOSTANDARD']:raise ValueError('routed name/standard mismatch: '+name)
  for pair in ref['differential_pairs']:
   if by_ball[pair['negative_ball']]['standard']!='LVDS33':raise ValueError('differential negative standard mismatch')
  result.update(physical_pad_table_checked=True,physical_pads_detail=rows)
 return result

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--area',type=Path);a=ap.parse_args()
 print(json.dumps(check(a.repo,a.area.read_text(encoding='utf-8',errors='replace') if a.area else None),indent=2))
