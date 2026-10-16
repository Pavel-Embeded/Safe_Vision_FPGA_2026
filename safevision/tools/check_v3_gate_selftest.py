"""Deliberate report corruption tests; these do not sign off any FPGA build."""
import argparse,json,re,sys,tempfile
from pathlib import Path
from check_v3_board import resource_gate,no_delay_ports,constraint_objects,exception_paths
from check_board_timing import assess,read_report,HEALTH_REQUIRED
from v3_sources import ROOT,FLOW
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--native-timing',type=Path,required=True);ap.add_argument('--native-spi-exceptions',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 results=[]
 def check(name,ok):
  results.append({'case':name,'pass':bool(ok)})
  if not ok:raise AssertionError(name)
 area='\n'.join('#%s %d out of %d 0.00%%'%x for x in [('lut',13720,19600),('reg',12740,19600),('bram',48,64),('bram32k',0,16),('dsp',19,29),('pll',3,4)])
 check('exact resource targets pass',resource_gate(area)['accepted'])
 for field,old,new in [('lut',13720,15681),('reg',12740,15681),('bram',48,55),('bram32k',0,2),('dsp',19,30),('pll',3,2)]:
  mutant=area.replace('#%s %d '%(field,old),'#%s %d '%(field,new))
  check('resource corruption '+field,not resource_gate(mutant)['accepted'])
 for name,mutant in [('missing',area.replace('#lut','lut')),('duplicate',area+'\n#lut 1 out of 19600 0.00%')]:
  try:resource_gate(mutant);detected=False
  except ValueError:detected=True
  check('reject '+name+' resource row',detected)
 # This controlled health fixture only supplies parser metadata. The timing
 # paths themselves are an unchanged native routed PLL probe report.
 health='\n'.join('%d. checking %s(0) (HIGH)'%(i,n) for i,n in enumerate(HEALTH_REQUIRED,1))
 health+='\nThere are 0 invalid constraints.\nThere are 0 combinational loops.\nThere are 0 clock pins that have no clock constraints.\nThere are 0 clocks whose clock frequency does not match the PLL setting.\n'
 health+='\n'.join('There are 0 %s.'%n for n in ('leaf clock pins driven by multiple clocks','clocks created on internal clock network','unexpandable clock sets'))
 timing=read_report(a.native_timing)
 check('unmodified native positive timing parses',assess(timing,health)['gate_accepted'])
 for kind in ('setup','hold','recovery','removal'):
  mutant=timing+'\nPath Group : injected\nMax : SWNS 0.000ns, STNS 0.000ns, 0 Viol Endpoints\nMin : HWNS 0.000ns, HTNS 0.000ns, 0 Viol Endpoints\nSlack : -0.001ns\nBegin Point : injected_source\nEnd Point : injected_dest\nCheck Type : '+kind+'\n'
  r=assess(mutant,health)
  check('reject negative '+kind,not r['gate_accepted'] and any('Negative '+kind in e for e in r['errors']))
 for name,mutant in [('missing fast min',re.sub(r'^Fast\s+\|\s+yes\s+yes', 'Fast | yes no',timing,flags=re.M)),('truncated path',timing+'\nSlack : 0.000ns\n'),('non routed',timing.replace('Confidence          : Routed','Confidence          : Estimated'))]:
  check('reject '+name,not assess(mutant,health)['gate_accepted'])
 check('reject missing health section',not assess(timing,'')['gate_accepted'])
 check('reject contradictory detailed health',not assess(timing,health.replace('There are 0 invalid constraints.','There are 1 invalid constraints.'))['gate_accepted'])
 good='1. checking no input delay (MEDIUM)\n-----\nThere are 1 input ports that have no input delay.\nrst_n\n2. checking next (HIGH)\n'
 check('classify one explicit asynchronous port',no_delay_ports(good,'input')==['rst_n'])
 try:no_delay_ports(good.replace('There are 1','There are 2'),'input');detected=False
 except ValueError:detected=True
 check('reject truncated unbudgeted-port detail',detected)
 # The fixture labels come from the current production audit, rather than a
 # historical count. This is gate-parser testing, not mapped-object evidence.
 audit=(ROOT/FLOW/'v3_cdc_audit.tcl').read_text(encoding='utf-8-sig')
 labels=re.findall(r'^v3_expect_objects \{([^}]+)\}',audit,re.M)
 check('current audit contains all 50 groups',len(labels)==50)
 fixture='label\tmatched_objects\n'+'\n'.join(name+'\t1' for name in labels)+'\n'
 check('all current object groups accepted',not constraint_objects(fixture,audit)[1])
 lines=fixture.splitlines()
 for name,mutant in (
  ('missing group','\n'.join(lines[:-1])),
  ('duplicate group',fixture+lines[-1]+'\n'),
  ('reordered groups','\n'.join(lines[:1]+lines[2:3]+lines[1:2]+lines[3:])),
  ('empty group',fixture.replace(labels[-1]+'\t1',labels[-1]+'\t0')),
  ('renamed group',fixture.replace(labels[-1],'unknown_group')),
  ('old 40 group fixture','\n'.join(lines[:41]))):
  check('reject constraint objects '+name,bool(constraint_objects(mutant,audit)[1]))
 sources=[(ROOT/FLOW/name).read_text(encoding='utf-8-sig') for name in ('v3_board.sdc','v3_cdc.sdc')]
 commands=[m[0] for source in sources for m in re.finditer(r'^set_(?:max_delay|multicycle_path)\b[^\n]*',source,re.M)]
 check('current path audit contains all 26 commands',len(commands)==26)
 fixture='\n'.join('1 1 0 0 '+command for command in commands)+'\n'
 # Native detailed witnesses stay mandatory for the narrow PI/PO zero-counter case.
 native_spi=a.native_spi_exceptions.read_text(encoding='utf-8-sig')
 details=re.sub(r'^\s*\d+\s+\d+\s+\d+\s+\d+\s+set_(?:max_delay|multicycle_path)[^\n]*$','',native_spi,flags=re.M)
 fixture+=details
 check('every actual exception command accepted',not exception_paths(fixture,sources)[1])
 lines=['1 1 0 0 '+command for command in commands]
 for name,mutant in (
  ('missing command','\n'.join(lines[:-1])+'\n'+details),
  ('duplicate command',fixture+lines[-1]+'\n'),
  ('ignored command',fixture.replace('1 1 0 0','1 0 0 1',1)),
  ('shadowed command',fixture.replace('1 1 0 0','1 0 1 0',1)),
  ('zero ordinary path command',fixture.replace('1 1 0 0 '+next(c for c in commands if c.startswith('set_max_delay')),'0 0 0 0 '+next(c for c in commands if c.startswith('set_max_delay')),1)),
  ('historical 19 row threshold','\n'.join(lines[:19])+'\n'+details)):
  check('reject actual exception '+name,bool(exception_paths(mutant,sources)[1]))
 a.output.parent.mkdir(parents=True,exist_ok=True)
 a.output.write_text(json.dumps({'scope':'gate-parser fault injection only; no board/resource acceptance','cases':results,'complete':all(x['pass'] for x in results)},indent=2),encoding='utf-8')
 print('PASS V3 strict gate fault injection cases='+str(len(results)));return 0
if __name__=='__main__':sys.exit(main())
