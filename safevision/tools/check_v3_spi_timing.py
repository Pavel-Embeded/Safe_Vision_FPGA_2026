"""Explicit PI/PO native-path evidence; does not waive general zero-hit MCPs.

TD 6.2 reports zero Total Paths for the specific PI/PO MCPs even while it prints
the endpoint, full routed path, and applied edge budget. Validate those details
independently. The only zero-count exception is one of these exact commands
with complete routed endpoint/edge witnesses; all ordinary paths stay strict.
"""
import json,re,sys
from pathlib import Path
PATTERN=re.compile(r'^Slack\s*:\s*([-+.0-9]+)ns\s*\nBegin Point\s*:\s*(.*?)\nEnd Point\s*:\s*(.*?)\nCheck Type\s*:\s*(setup|hold)\s*\nProcess\s*:\s*(slow|fast)\s*\nBudget\s*:\s*([-+.0-9]+)ns(?:[ \t]*\{([^\n]*)\})?',re.M)
def check(text):
 errors=[];witness=[]
 if not re.search(r'^Confidence\s*:\s*Routed\s*$',text,re.M):errors.append('not routed')
 if not re.search(r'^Check Corner\s*:\s*Both \(Slow and Fast\)\s*$',text,re.M):errors.append('missing corners')
 # Find actual groups by line starts. A group header contains only the two
 # command lines and whitespace, never another path/group/report section.
 raw=list(re.finditer(r'^Path Group\s*:\s*\n((?:set_multicycle_path[^\n]*\n){2})\s*\nType\s*:\s*MCP\s*$',text,re.M))
 all_groups=list(re.finditer(r'^Path Group\s*:',text,re.M));commands=[]
 for clock,budget,setup,hold in [('sd_fast',40.0,2,3),('sd_ident',5000.0,250,499)]:
  for direction in ('input','output'):
   if direction=='input':
    wanted=[f'set_multicycle_path -setup -from [get_clocks {clock}] -to [get_pins {{sd_miso_syn_*.ipad}}] {setup}',
            f'set_multicycle_path -hold -end -from [get_clocks {clock}] -to [get_pins {{sd_miso_syn_*.ipad}}] {setup-1}']
   else:
    wanted=[f'set_multicycle_path -setup -start -from [get_clocks board_clk] -through [get_ports {{sd_mosi}}] -to [get_clocks {clock}] {setup}',
            f'set_multicycle_path -hold -start -from [get_clocks board_clk] -through [get_ports {{sd_mosi}}] -to [get_clocks {clock}] {hold}']
   matches=[(i,m) for i,m in enumerate(raw) if m[1].strip().splitlines()==wanted]
   if len(matches)!=1:errors.append(f'{clock} {direction}: missing/ambiguous exact command pair');continue
   i,m=matches[0];end=next((h.start() for h in all_groups if h.start()>m.start()),len(text));section=text[m.end():end]
   commands.extend(wanted)
   paths=[]
   for p in PATTERN.finditer(section):
    slack,begin,finish,kind,corner,actual,edges=p.groups()
    begin_name=begin.split(' (')[0].strip();end_name=finish.split(' (')[0].strip()
    source_clock=clock if direction=='input' else 'board_clk'
    target_clock='board_clk' if direction=='input' else clock
    if f'clock {source_clock} ' not in begin or f'clock {target_clock} ' not in finish:
     errors.append(f'{clock} {direction}: wrong launch/capture clock')
    if abs(float(actual)-(budget if kind=='setup' or direction=='output' else 0.0))>0.001:
     errors.append(f'{clock} {direction}: unexpected {kind} budget {actual}')
    if direction=='input':
     next_path=PATTERN.search(section,p.end());body=section[p.end():next_path.start() if next_path else len(section)]
     # A slice can contain unrelated physical register names. Native TD prints
     # the actual captured logical net on the final register timing row; require
     # that first RX bit rather than trusting an arbitrary packed slice name.
     rx_alias=bool(re.search(r'\bnet:\s+(?:(?:player/)?u_spi|spi)/rx_sr\[0\](?:[,\s]|$)',body))
     named_rx=bool(re.fullmatch(r'(?:(?:(?:player/)?u_spi|spi)/rx_sr_reg\[0\][^ ]*|sd_miso_syn_\d+\.ipad)',end_name))
     if begin_name!='sd_miso' or not (rx_alias or named_rx):
      errors.append(f'{clock} input: wrong physical input/capture path')
     if not re.search(r'pin:\s+sd_miso_syn_\d+\.ipad(?:\s|$)',body):
      errors.append(f'{clock} input: missing actual MISO PAD path')
    elif end_name!='sd_mosi':
     errors.append(f'{clock} output: unexpected endpoint {end_name}')
    if float(slack)<0:errors.append(f'{clock} {direction}: negative {kind} {slack}')
    paths.append({'begin':begin_name,'end':end_name,'type':kind,'corner':corner,'budget_ns':float(actual),'slack_ns':float(slack),'source_edge':'fall' if 'falling edge triggered' in begin else 'rise'})
   for kind in ('setup','hold'):
    required={'sd_mosi'} if direction=='output' else {'sd_miso'}
    present={p['end'] if direction=='output' else p['begin'] for p in paths if p['type']==kind}
    if present!=required:errors.append(f'{clock} {direction}: missing {kind} endpoint witness')
    if direction=='input' and not any(x['type']==kind and x['source_edge']=='fall' for x in paths):errors.append(f'{clock} input: missing physical falling-SCLK {kind} witness')
   witness.append({'clock':clock,'direction':direction,'paths':paths})
 return {'accepted':not errors,'errors':errors,'witness':witness,'commands':commands,'scope':'only these exact native routed SPI IO MCP edge budgets'}

def check_cs(text):
 """CS has ordinary IO constraints, never the MOSI enable MCP."""
 errors=[];paths=[]
 for p in PATTERN.finditer(text):
  slack,begin,finish,kind,corner,budget,edges=p.groups()
  if finish.split(' (')[0].strip()!='sd_ncs':continue
  clock=re.search(r'clock (sd_fast|sd_ident) ',finish)
  if not clock:errors.append('CS missing exact SD capture clock');continue
  if not re.fullmatch(r'sd_ncs_syn_\d+\.osclk',begin.split(' (')[0].strip()) or 'falling edge triggered by clock board_clk ' not in begin:
   errors.append('CS is not driven from its falling REF PAD register')
  if abs(float(budget)-10.0)>0.001:errors.append('CS ordinary half REF budget is not 10ns')
  if float(slack)<0:errors.append('CS negative '+kind)
  paths.append({'clock':clock[1],'kind':kind,'corner':corner,'budget_ns':float(budget),'slack_ns':float(slack)})
 if {(p['clock'],p['kind']) for p in paths}!={(c,k) for c in ('sd_fast','sd_ident') for k in ('setup','hold')}:
  errors.append('CS ordinary setup/hold witnesses missing for one or both SD modes')
 return {'accepted':not errors,'errors':errors,'paths':paths}
def main():
 import argparse
 parser=argparse.ArgumentParser();parser.add_argument('--exceptions',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);a=parser.parse_args()
 result=check(a.exceptions.read_text(encoding='utf-8-sig'));a.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
 print('SPI detailed witnesses '+('PASS' if result['accepted'] else 'FAIL'))
 return 0 if result['accepted'] else 1
if __name__=='__main__':sys.exit(main())
