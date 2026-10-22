"""Freeze an independently validated read-start diagnostic; no application claim."""
import argparse,hashlib,json,os,re,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
from check_board_timing import assess,read_report
from run_v3_board import invoke,source_commit_binding
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.write_bytes((json.dumps(v,indent=2)+'\n').encode())
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--run-dir',type=Path,required=True);ap.add_argument('--source-ref',required=True);a=ap.parse_args()
 run=a.run_dir.resolve();native=run/'native';sim=run/'simulation_02';project='safevision/platform/anlogic_eg4s20_hx4s20c/project/adapter_readrotate_26101730/'
 record=read(native/'native.acceptance.json');deps={};proof={}
 for name,digest in record['source_sha256'].items():
  key=project+name if name in ('probe.adc','probe.sdc') else name;assert sha(ROOT/key)==digest;deps[key]=digest
 assert sha(native/'route.db')==record['routed_db_sha256']
 for i,phase in enumerate(('route','final')):
  v=assess(read_report(native/(phase+'.timing')),read_report(native/(phase+'.check')))
  assert v['timing_passed'] and v['gate_accepted'] and v==record['assessments'][i]
  assert all(row['reported_min_ns'] is not None and row['reported_min_ns']>=0 for row in v['minima'].values())
 results=read(sim/'results.json');assert results['complete'] and len(results['results'])==1
 entry=results['results'][0];assert entry['status']=='PASS' and not entry['source_overrides'] and entry['checks']==127 and entry['data_comparisons']==3840
 case=sim/'tb_v3_adapter_readrotate_trace';text=(case/'sim.log').read_text(encoding='utf-8');assert '$finish called' in text and 'done, errors=0 comparisons=3840' in text
 for marker in ('odd path detects exactly the injected error','even path detects exactly the injected error','passive App observer detects injected payload on exact edge','six even rounds issue exactly480 rotated requests'):assert '[PASS] '+marker in text
 assert '[FAIL]' not in text
 for name,digest in read(case/'sources.sha256.json').items():assert sha(ROOT/name)==digest;deps[name]=digest
 for p in case.iterdir():
  if p.name in ('sim.log','sim.console.log','compile.log','elab.log','sources.sha256.json'):proof['simulation/'+p.name]=p
 proof['simulation/results.json']=sim/'results.json'
 controls=read(run/'negative.index.json');assert {c['mutation'] for c in controls}=={'read_rotation_disabled','read_alignment_disabled'}
 for c in controls:
  folder=run/c['mutation'];mutant=folder/'mutant.v';neg=folder/'simulation/tb_v3_adapter_readrotate_trace';t=(neg/'sim.log').read_text(encoding='utf-8')
  assert c['detected'] and c['normal_completion'] and c['process_exit']==1 and '$finish called' in t and c['required_marker'] in t
  assert [int(x) for x in re.findall(r'errors=(\d+)',t)]==c['error_counts'] and any(c['error_counts'])
  assert not re.search(r'(?im)^\s*(Fatal:|FATAL\b|ERROR:|SKIP\b)|watchdog',t)
  s=(ROOT/c['target']).read_text(encoding='utf-8')
  for patch in c['patch']:assert s.count(patch['before'])==1;s=s.replace(patch['before'],patch['after'])
  assert s==mutant.read_text(encoding='utf-8') and sha(ROOT/c['target'])==c['original_sha256'] and sha(mutant)==c['mutated_sha256']
  for name,digest in read(neg/'sources.sha256.json').items():assert sha(mutant if name==c['target'] else ROOT/name)==digest
  for p in (folder/'case.json',mutant,folder/'simulation/results.json',neg/'sim.log',neg/'sources.sha256.json'):proof['negative/'+c['mutation']+'/'+p.name]=p
 for name in ('native.sources.json',):deps[project+name]=sha(ROOT/project/name)
 for n in ('run_adapter_readrotate_trace.py','finalize_adapter_readrotate_trace.py','generate_adapter_readrotate_vectors.py','run_v3_board.py','check_board_timing.py'):deps['safevision/tools/'+n]=sha(ROOT/'safevision/tools'/n)
 binding=source_commit_binding(ROOT,ROOT,a.source_ref,deps);assert binding['verified'],binding
 out=ROOT/'artifacts/diagnostics/adapter_readrotate_26101730';assert not out.exists();out.mkdir(parents=True)
 for name in deps:
  p=out/'source'/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,p)
 for name,p in proof.items():dst=out/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dst)
 for p in native.iterdir():
  if p.is_file():dst=out/'native'/p.name;dst.parent.mkdir(exist_ok=True);shutil.copyfile(p,dst)
 assert sha(out/'native/route.db')==record['routed_db_sha256']
 assert all(sha(out/'source'/name)==digest for name,digest in deps.items())
 assert all(sha(out/name)==sha(p) for name,p in proof.items())
 for phase in ('route','final'):
  assert assess(read_report(out/'native'/(phase+'.timing')),read_report(out/'native'/(phase+'.check')))['gate_accepted']
 shutil.copyfile(ROOT/'docs/v3/adapter_readrotate_26101730.md',out/'README.md')
 before={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()}
 exe=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe');exe_hash=sha(exe)
 bit=out/'SafeVision_ADAPTER_READROTATE_26101730.bit';pending=out/(bit.name+'.pending');tcl=out/'bitgen.tcl'
 tcl.write_bytes(('if {[catch {\nimport_db {'+(out/'native/route.db').as_posix()+'}\nbitgen -bit {'+pending.as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "READROTATE BITGEN COMPLETE"\nexit 0\n').encode())
 _,log=invoke(exe,tcl,out/'bitgen.console.log',os.environ.copy());assert 'READROTATE BITGEN COMPLETE' in log and pending.stat().st_size>0
 assert sha(exe)==exe_hash and all(sha(out/n)==digest for n,digest in before.items()) and all(sha(ROOT/n)==digest for n,digest in deps.items());pending.replace(bit)
 save(out/'probe.index.json',dict(id='26101730',diagnostic_only=True,hardware_verified=False,production_application=False,source_commit_binding=binding,source_sha256=deps,sta_minima=record['assessments'][-1]['minima'],simulation_checks=127,simulation_comparisons=3840,negative_controls=controls,read_offsets=[1,2,3],model_read_addresses_ideal=True,expected_rounds=12,expected_total_words=46272,sha256=sha(bit),bitstream=bit.name,github_upload_performed=False))
 save(out/'payload.sha256.json',{p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()})
 print('READROTATE30 DIAGNOSTIC PACKAGED '+str(bit)+' '+sha(bit));return 0
if __name__=='__main__':sys.exit(main())
