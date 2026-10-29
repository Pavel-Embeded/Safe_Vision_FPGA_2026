


import argparse,hashlib,json,re,sys
from pathlib import Path
from run_v3_board import invoke,source_commit_binding
from v3_sources import snapshot
from check_v3_board import check

REQUIRED={'tb_v3_sd_pixel_gap','tb_v3_board_diagnostics','tb_v3_frame_snapshot',
 'tb_v3_controls','tb_v3_controls_period','tb_v3_board_top','tb_v3_board_query_catalog',
 'tb_v3_status_layers','tb_v3_video_cache','tb_v3_supervisor','tb_v3_supervisor_tick',
 'tb_v3_video_final_base','tb_v3_video_final_hd','tb_v3_video_control'}
MUTANTS={'key2_old_gate','diagnostic_swapped_error','snapshot_changes_before_frame'}

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def inside(root,name):
 p=(root/name).resolve()
 if not p.is_relative_to(root) or not p.is_file():raise ValueError('invalid/missing proof input: '+name)
 return p

def functional(root,index):
 data=read(index);assert data['diagnostic_only'] is True
 assert {x['top'] for x in data['positive']}==REQUIRED and len(data['positive'])==len(REQUIRED)
 assert {x['case'] for x in data['negative']}==MUTANTS and len(data['negative'])==len(MUTANTS)
 dependencies={index.relative_to(root).as_posix():sha(index)}
 for negative,rows in ((False,data['positive']),(True,data['negative'])):
  for row in rows:
   folder=(root/row['evidence']).resolve();assert folder.is_relative_to(root)
   result=read(folder/'result.json');top=row['top'];assert result['top']==top
   log=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
   numbers=[int(v) for v in re.findall(r'errors\s*=\s*(\d+)',log)]
   assert '$finish called' in log and numbers and '[PASS]' in log
   assert re.search(r'PASS\s+'+re.escape(top)+r'\b|\[TB\]\s*'+re.escape(top)+r'\s+done',log)
   assert not re.search(r'(?im)(\[SKIP\]|^\s*(?:ERROR:|Fatal:|FATAL\b|SKIP\b))',log)
   if negative:
    assert result['status']=='FAIL' and any(numbers) and '[FAIL]' in log
    mutation=read(folder/'mutation.json');assert mutation['target']==row['target']
    original=inside(root,row['target']).read_text(encoding='utf-8')
    assert original.count(mutation['before'])==1
    assert (folder/'mutant.v').read_text(encoding='utf-8')==original.replace(mutation['before'],mutation['after'])
   else:assert result['status']=='PASS' and not any(numbers) and '[FAIL]' not in log
   for name,digest in read(folder/'sources.sha256.json').items():
    path=(folder/'mutant.v') if negative and name==row['target'] else inside(root,name)
    assert sha(path)==digest,'stale proof source: '+name
    if not (negative and name==row['target']):dependencies[name]=digest
   for path in folder.rglob('*'):
    if path.is_file():dependencies[path.relative_to(root).as_posix()]=sha(path)
 return dependencies

def main():
 if not __debug__:raise RuntimeError('diagnostic gates require Python assertions enabled')
 ap=argparse.ArgumentParser();ap.add_argument('--repo',required=True,type=Path);ap.add_argument('--td-run',required=True,type=Path)
 ap.add_argument('--functional-index',required=True,type=Path);ap.add_argument('--source-repo',required=True,type=Path)
 ap.add_argument('--source-ref',default='HEAD');ap.add_argument('--output',required=True,type=Path)
 ap.add_argument('--td-exe',type=Path,default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'))
 a=ap.parse_args();root=a.repo.resolve();run=a.td_run.resolve();out=a.output.resolve()
 assert not out.exists() or not any(out.iterdir()),'new empty output required'
 deps={**snapshot(root),**functional(root,inside(root,a.functional_index.as_posix()))}
 deps[Path(__file__).resolve().relative_to(root).as_posix()]=sha(Path(__file__))
 binding=source_commit_binding(root,a.source_repo.resolve(),a.source_ref,deps)
 assert binding['verified'],binding
 approved={}
 for mode in ('base','hd'):
  record=read(run/mode/'build.manifest.json');assert record['status']=='PASS' and record['source_unchanged']
  assert all(deps.get(name)==value for name,value in record['sources'].items()),'native source snapshot differs'
  gate=check(run/mode,root);assert gate['gate_accepted'] and gate['timing_passed'],gate['errors']
  approved[mode]=gate
 def unchanged():
  assert all(sha(inside(root,name))==value for name,value in deps.items()),'source/proof changed'
  for gate in approved.values():
   assert all(sha(Path(item['path']))==item['sha256'] for item in gate['reports']),'routed evidence changed'
 unchanged();out.mkdir(parents=True,exist_ok=True)
 import os
 env=os.environ.copy();records=[]
 for mode in ('base','hd'):
  name='SafeVision_'+mode.upper()+'_26101610_DIAGNOSTIC.bit'
  bit=out/name;pending=out/(name+'.pending');tcl=out/(mode+'_bitgen.tcl')
  tcl.write_text('if {[catch {\n import_db {'+(run/mode/'route.db').as_posix()+'}\n bitgen -bit {'+pending.as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "V3 DIAGNOSTIC BITGEN COMPLETE"\nexit 0\n',encoding='ascii')
  unchanged();_,log=invoke(a.td_exe,tcl,out/(mode+'_bitgen.console.log'),env)
  assert 'V3 DIAGNOSTIC BITGEN COMPLETE' in log and pending.stat().st_size>0
  unchanged();pending.replace(bit)
  records.append({'mode':mode,'file':name,'bytes':bit.stat().st_size,'sha256':sha(bit),'gate':approved[mode]})
 result={'id':'26101610','diagnostic_only':True,'hardware_verified':False,'production_113_28_gate_current':False,
  'positive_native_tests':len(REQUIRED),'strict_semantic_mutants':len(MUTANTS),'source_commit_binding':binding,
  'source_and_proof_sha256':deps,'bitstreams':records,'github_push_performed':False}
 (out/'diagnostic.index.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'diagnostic_only':True,'source_commit':binding['commit'],'bitstreams':[{k:v for k,v in x.items() if k!='gate'} for x in records]},indent=2))
if __name__=='__main__':main()
