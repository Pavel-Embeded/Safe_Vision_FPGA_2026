"""Reject GUI, Tcl and ADC drift; use unchanged native reports for parser checks."""
import argparse,json,shutil,sys
from pathlib import Path
from v3_sources import ROOT,FLOW,scope,build_parameters,gui_project,check_gui,native_parameters,physical_constraint_files
from check_board_timing import read_report
from check_v3_board import no_delay_ports

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--run-dir',type=Path,required=True);ap.add_argument('--native-base',type=Path,required=True);a=ap.parse_args()
 root=a.repo.resolve();out=a.run_dir.resolve();source=out/'source'
 if out.exists():raise ValueError('use a new empty selftest directory')
 out.mkdir(parents=True)
 for rel in scope(root):
  target=source/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/rel,target)
 rows=[]
 def check(name,condition):
  rows.append({'case':name,'pass':bool(condition)})
  if not condition:raise AssertionError(name)
 def rejects(name,call):
  try:call();bad=False
  except (ValueError,AssertionError):bad=True
  check(name,bad)
 native=native_parameters(root,a.native_base.resolve());check('every effective BASE native parameter acknowledged',len(native)==len(build_parameters(root,'base')))
 folder=source/FLOW;common=folder/'v3_build_parameters.tcl';original=common.read_text(encoding='utf-8')
 # Test a distinct mode override, independent of the selected production value.
 import re
 text=re.sub(r'set_param rtl min_ripple_len \d+','set_param rtl min_ripple_len 32',original);common.write_text(text,encoding='utf-8')
 override=folder/'v3_build_parameters_hd.tcl';override.write_text('set_param rtl min_ripple_len 16\n',encoding='ascii')
 check('BASE common32 and HD override16 resolve separately',('rtl','min_ripple_len','32') in build_parameters(source,'base') and ('rtl','min_ripple_len','16') in build_parameters(source,'hd'))
 for mode in ('base','hd'):gui_project(source,mode);check(mode+' explicit GUI/CLI dependencies and constraints match',check_gui(source,mode)['top']=='safevision_v3_top')
 for name,bad in [('disabled setup optimization',text.replace('route timing on','route timing off')),('disabled hold repair',text.replace('route fix_hold on','route fix_hold off')),('duplicate parameter',text+'set_param rtl min_ripple_len 32\n'),('unknown parameter',text+'set_param place bypass_checks on\n'),('extra Tcl command',text+'exit 0\n')]:
  common.write_text(bad,encoding='utf-8');rejects(name,lambda:build_parameters(source,'base'))
 common.write_text(text,encoding='utf-8');override.write_text('set_param rtl min_ripple_len 16\nset_param rtl min_ripple_len 32\n',encoding='ascii');rejects('duplicate mode override',lambda:build_parameters(source,'hd'));override.write_text('set_param rtl min_ripple_len 16\n',encoding='ascii')
 physical=folder/'v3_physical.adc';good=physical.read_bytes();physical.write_bytes(good+b'\nset_pin_assignment {clk} {LOCATION=R8;}\n');rejects('internal ADC cannot alter board pin contract',lambda:physical_constraint_files(source));physical.write_bytes(good)
 check('BASE selects its reviewed mode-specific internal placement',[p.name for p in physical_constraint_files(source,'base')]==['v3_board.adc','v3_physical_base.adc'])
 check('HD retains the common reviewed PHY placement',[p.name for p in physical_constraint_files(source,'hd')]==['v3_board.adc','v3_physical.adc'])
 physical=folder/'v3_physical_base.adc';good=physical.read_bytes();physical.write_bytes(good+b'\nset_pin_assignment {clk} {LOCATION=R8;}\n')
 rejects('BASE physical override cannot alter shared IO',lambda:physical_constraint_files(source,'base'))
 rejects('inactive physical override still receives validation',lambda:physical_constraint_files(source,'hd'));physical.write_bytes(good)
 base_gui=folder/'base/safevision_v3_base.al';good=base_gui.read_bytes();base_gui.write_bytes(good.replace(b'v3_physical_base.adc',b'v3_physical.adc'));rejects('BASE GUI cannot silently use HD physical selection',lambda:check_gui(source,'base'));base_gui.write_bytes(good)
 gui=folder/'hd/safevision_v3_hd.al';good=gui.read_bytes();gui.write_bytes(good.replace(b'<min_ripple_len>16</min_ripple_len>',b'<min_ripple_len>32</min_ripple_len>'));rejects('GUI parameter drift',lambda:check_gui(source,'hd'));gui.write_bytes(good)
 health_file=a.native_base/'route.check';health=read_report(health_file)
 check('native CRLF report bytes retained',b'\r\n' in health_file.read_bytes());check('native six input ports parsed',len(no_delay_ports(health,'input'))==6);check('native eleven output ports parsed',len(no_delay_ports(health,'output'))==11)
 rejects('truncated native I/O detail',lambda:no_delay_ports(health.replace('\tbtn_auto\n',''),'input'))
 result={'complete':True,'cases':rows,'scope':'configuration/report-parser fault injection only; no FPGA signoff'}
 (out/'results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('PASS V3 configuration controls='+str(len(rows)));return 0
if __name__=='__main__':sys.exit(main())
