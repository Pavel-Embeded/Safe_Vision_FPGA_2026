"""BASE-only UART fault investigation; never a production113/28 acceptance.

Requires9 fresh positive native simulations,3 detected semantic mutants,
unchanged source bytes, strict routed all-corner STA, and committed Git blobs.
"""
import argparse,hashlib,json,re,os
from pathlib import Path
from v3_sources import snapshot
from run_v3_board import invoke,source_commit_binding
from check_v3_board import check

REQUIRED={'tb_v3_diag_query','tb_v3_diag_board','tb_v3_command_catalog','tb_v3_uart_link_catalog',
 'tb_v3_board_top','tb_v3_board_query_catalog','tb_v3_controls','tb_v3_controls_period','tb_v3_sd_pixel_gap'}
MUTANTS={'tag_mismatch','swapped_crc','old_key2_gate'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def inside(root,name):
 p=(root/name).resolve()
 if not p.is_relative_to(root) or not p.is_file():raise ValueError('missing proof dependency: '+name)
 return p
def functional(root,index):
 data=read(index);assert data['diagnostic_only'] is True
 assert {x['top'] for x in data['positive']}==REQUIRED and len(data['positive'])==len(REQUIRED)
 assert {x['case'] for x in data['negative']}==MUTANTS and len(data['negative'])==len(MUTANTS)
 deps={index.relative_to(root).as_posix():sha(index)}
 for negative,rows in ((False,data['positive']),(True,data['negative'])):
  for row in rows:
   folder=(root/row['evidence']).resolve();assert folder.is_relative_to(root)
   result=read(folder/'result.json');top=row['top'];assert result['top']==top
   log=(folder/'sim.log').read_text(errors='replace')
   numbers=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',log)]
   assert numbers and '$finish called' in log
   assert re.search(r'PASS\s+'+re.escape(top)+r'\b|\[TB\]\s*'+re.escape(top)+r'\s+done',log)
   assert not re.search(r'(?im)(\[SKIP\]|^\s*(ERROR:|Fatal:|FATAL\b|SKIP\b))',log)
   if negative:
    assert result['status']=='FAIL' and any(numbers) and '[FAIL]' in log
    change=read(folder/'mutation.json');original=inside(root,row['target']).read_text(encoding='utf-8')
    assert change['target']==row['target'] and original.count(change['before'])==1
    assert (folder/'mutant.v').read_text(encoding='utf-8')==original.replace(change['before'],change['after'])
   else:assert result['status']=='PASS' and not any(numbers) and '[PASS]' in log and '[FAIL]' not in log and not result['source_overrides']
   for name,digest in read(folder/'sources.sha256.json').items():
    path=folder/'mutant.v' if negative and name==row['target'] else inside(root,name)
    assert sha(path)==digest,'stale simulation dependency: '+name
    if not (negative and name==row['target']):deps[name]=digest
   for p in folder.rglob('*'):
    if p.is_file():deps[p.relative_to(root).as_posix()]=sha(p)
 return deps
def main():
 if not __debug__:raise RuntimeError('assertions must remain enabled')
 ap=argparse.ArgumentParser();ap.add_argument('--repo',required=True,type=Path);ap.add_argument('--native-run',required=True,type=Path)
 ap.add_argument('--source-repo',required=True,type=Path);ap.add_argument('--source-ref',default='HEAD')
 ap.add_argument('--output',required=True,type=Path);ap.add_argument('--check-only',action='store_true')
 ap.add_argument('--td-exe',type=Path,default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe'))
 a=ap.parse_args();root=a.repo.resolve();native=a.native_run.resolve();out=a.output.resolve()
 index=inside(root,'evidence/v3/uart_diag_26101611/functional.index.json')
 deps={**snapshot(root),**functional(root,index)}
 tool=Path(__file__).resolve();assert tool.is_relative_to(root);deps[tool.relative_to(root).as_posix()]=sha(tool)
 record=read(native/'build.manifest.json');assert record['mode']=='base' and record['status']=='PASS' and record['source_unchanged']
 assert all(deps.get(name)==value for name,value in record['sources'].items()),'native build is not this source snapshot'
 gate=check(native,root);assert gate['gate_accepted'] and gate['timing_passed'],gate['errors']
 binding=source_commit_binding(root,a.source_repo.resolve(),a.source_ref,deps);assert binding['verified'],binding
 def unchanged():
  assert all(sha(inside(root,name))==digest for name,digest in deps.items()),'source/proof changed'
  assert all(sha(Path(item['path']))==item['sha256'] for item in gate['reports']),'routed evidence changed'
 unchanged()
 if a.check_only:print(json.dumps(dict(accepted=True,diagnostic_only=True,source_commit=binding['commit'])));return
 assert not out.exists() or not any(out.iterdir()),'new empty output required'
 out.mkdir(parents=True,exist_ok=True)
 bit=out/'SafeVision_BASE_26101611_UART_DIAG.bit';pending=out/(bit.name+'.pending')
 tcl=out/'base_bitgen.tcl'
 tcl.write_text('if {[catch {\n import_db {'+(native/'route.db').as_posix()+'}\n bitgen -bit {'+pending.as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "V3 UART DIAGNOSTIC BITGEN COMPLETE"\nexit 0\n',encoding='ascii')
 _,log=invoke(a.td_exe,tcl,out/'base_bitgen.console.log',os.environ.copy())
 assert 'V3 UART DIAGNOSTIC BITGEN COMPLETE' in log and pending.is_file() and pending.stat().st_size>0
 unchanged();pending.replace(bit)
 result=dict(id='26101611',diagnostic_only=True,mode='BASE',hardware_verified=False,production_113_28_gate_current=False,
  full_hd_candidate_built=False,positive_native_tests=9,strict_semantic_mutants=3,source_commit_binding=binding,
  source_and_proof_sha256=deps,bitstream=bit.name,bytes=bit.stat().st_size,sha256=sha(bit),native_gate=gate,github_push_performed=False)
 (out/'diagnostic.index.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:v for k,v in result.items() if k not in ('native_gate','source_and_proof_sha256')},indent=2))
if __name__=='__main__':main()
