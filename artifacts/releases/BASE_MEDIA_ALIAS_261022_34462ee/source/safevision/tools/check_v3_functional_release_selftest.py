"""Prove release rejection on raw-log, source, vector and approval drift."""
import argparse,json,os,shutil,subprocess,sys
from pathlib import Path
from v3_sources import ROOT
from v3_functional_release import acceptance,unchanged,DEFAULT_MANIFEST

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--run-dir',type=Path,required=True);a=ap.parse_args()
 root=a.repo.resolve();out=a.run_dir.resolve();copy=out/'source'
 if out.exists():raise ValueError('use a new empty selftest directory')
 initial,proof=acceptance(root);out.mkdir(parents=True)
 for name in proof:
  target=copy/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/name,target)
 rows=[]
 def check(name,ok):
  rows.append({'case':name,'pass':bool(ok)})
  if not ok:raise AssertionError(name)
 def rejected():
  try:acceptance(copy);return False
  except (ValueError,AssertionError):return True
 result,frozen=acceptance(copy);check('unchanged complete native proof accepted',result['positive_native_tests']==initial['positive_native_tests']>=106 and result['strict_normal_ending_mutants']==initial['strict_normal_ending_mutants']>=19 and unchanged(copy,frozen))
 index=json.loads((copy/DEFAULT_MANIFEST).read_text(encoding='utf-8'));case=copy/index['positive_tests'][0]['evidence'];log=case/'sim.log';good=log.read_bytes()
 log.write_bytes(good+b'\n[MODEL][FAIL] release sentinel\n');check('prefixed failure in raw log rejected',rejected());log.write_bytes(good)
 log.write_bytes(good.replace(b'$finish called',b'finish removed'));check('missing normal completion rejected',rejected());log.write_bytes(good)
 source=copy/'safevision/rtl/control/v3_supervisor.v';good=source.read_bytes();source.write_bytes(good+b'\n// isolated source drift\n');check('changed functional source rejected',rejected());source.write_bytes(good)
 generated=next(copy/name for name in proof if name.endswith('.mem') and ('/fixtures/' in name or '/positive/' in name));good=generated.read_bytes();generated.write_bytes(bytes([good[0]^1])+good[1:]);check('changed generated vector rejected',rejected());generated.write_bytes(good)
 manifest=copy/DEFAULT_MANIFEST;good=manifest.read_bytes();mutated=json.loads(good);mutated['negative_controls']=[c for c in mutated['negative_controls'] if c['mutation']!='tick_predict_off_by_one'];manifest.write_bytes(json.dumps(mutated).encode('utf-8'));check('missing required semantic mutant rejected',rejected());manifest.write_bytes(good)
 for mutation in ('board_query_binding','uart_fractional_step','control_signed_range','control_catalog_binding'):
  mutated=json.loads(good);mutated['negative_controls']=[c for c in mutated['negative_controls'] if c['mutation']!=mutation];manifest.write_bytes(json.dumps(mutated).encode('utf-8'));check('missing '+mutation+' mutant rejected',rejected());manifest.write_bytes(good)
 mutated=json.loads(good);mutated['positive_tests']=[c for c in mutated['positive_tests'] if c['top']!='tb_v3_control_decode_equivalence'];manifest.write_bytes(json.dumps(mutated).encode('utf-8'));check('missing exact control reference test rejected',rejected());manifest.write_bytes(good)
 mutated=json.loads(good);mutated['positive_tests']=[c for c in mutated['positive_tests'] if c['top']!='tb_v3_control_catalog_equivalence'];manifest.write_bytes(json.dumps(mutated).encode('utf-8'));check('missing board catalog reference test rejected',rejected());manifest.write_bytes(good)
 compile_log=next(copy/name for name in proof if name.endswith('/compile.log'));good=compile_log.read_bytes();compile_log.write_bytes(good+b'\nchanged after approval\n');check('any approved transcript byte drift detected',not unchanged(copy,frozen));compile_log.write_bytes(good)
 env=os.environ.copy();env['PYTHONPATH']=str(root/'safevision/tools')
 code='import sys\nfrom pathlib import Path\nfrom v3_functional_release import acceptance\ntry: acceptance(Path(sys.argv[1]))\nexcept RuntimeError: sys.exit(0)\nsys.exit(1)\n'
 p=subprocess.run([sys.executable,'-O','-c',code,str(copy)],env=env,capture_output=True);check('Python optimized assertions cannot bypass gate',p.returncode==0)
 check('all fixtures restored',unchanged(copy,frozen) and acceptance(copy)[0]['accepted'])
 (out/'results.json').write_text(json.dumps({'complete':True,'cases':rows,'scope':'release gating fault injection only; no FPGA acceptance'},indent=2)+'\n',encoding='utf-8');print('PASS functional release controls='+str(len(rows)));return 0
if __name__=='__main__':sys.exit(main())
