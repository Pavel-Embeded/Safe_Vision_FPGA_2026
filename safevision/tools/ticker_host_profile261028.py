"""Version-bind preserved configuration/geometry/period tests to ticker BASE."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
BASELINE='09faac2e8fa718c9f92ef4a5013b68003ec8afe6'
ROOT=Path(__file__).resolve().parents[2]
PROFILES={
 'configuration':('exercise_configuration_26102004.ps1','audit_configuration_26102004.py','26102004',3),
 'geometries':('exercise_geometries_26102004.ps1','audit_geometries.py','26101802',2),
 'periods':('exercise_periods_26102004.ps1','audit_periods.py','26101802',2)}
def require(ok,message):
 if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def frozen(root,name):
 relative='safevision/tools/host/'+name;path=root/relative;raw=path.read_bytes()
 expected=subprocess.check_output(['git','-C',str(root),'cat-file','blob',BASELINE+':'+relative])
 require(raw==expected,'preserved host script changed: '+relative)
 return path,raw
def prepare(root,out):
 require(not out.exists()and str(out.resolve()).isascii(),'fresh ASCII host output required');out.mkdir(parents=True)
 result={}
 for stage,(script,audit,old,count)in PROFILES.items():
  path,raw=frozen(root,script);text=raw.decode('utf-8-sig')
  require(text.count('0x26102004')==1,'unexpected source firmware guard')
  derived=text.replace('0x26102004','0x26102801').encode('utf-8');dest=out/(stage+'.ps1');dest.write_bytes(derived)
  result[stage]=dict(source=path.relative_to(root).as_posix(),source_sha256=sha(raw),derived_file=dest.name,derived_sha256=sha(derived),replacement=dict(before='0x26102004',after='0x26102801',occurrences=1))
 (out/'profile.json').write_text(json.dumps(dict(schema=1,firmware_id='26102801',stages=result),indent=2)+'\n','utf-8')
 return result
def replay(root,captures,out):
 require(not out.exists(),'fresh supplementary audit output required');out.mkdir(parents=True);reports={}
 for stage,(script,audit,old,count)in PROFILES.items():
  path,raw=frozen(root,audit);text=raw.decode('utf-8-sig');require(text.count(old)==count,'unexpected audit firmware occurrences')
  transformed=text.replace(old,'26102801')
  # Keep original __file__ so the unmodified dependency resolution reads the
  # current repository decoder. Only the guarded firmware literal changes.
  log=out/(stage+'.console.log')
  runner="import sys;from pathlib import Path;p=Path(sys.argv[1]);old=sys.argv[3];t=p.read_text('utf-8-sig');capture=sys.argv[2];sys.argv=[str(p),capture];exec(compile(t.replace(old,'26102801'),str(p),'exec'),{'__name__':'__main__','__file__':str(p)})"
  with log.open('w',encoding='utf-8')as f:code=subprocess.run([sys.executable,'-B','-c',runner,str(path),str(captures/stage),old],stdout=f,stderr=subprocess.STDOUT).returncode
  require(code==0,'supplementary byte audit failed: '+str(log))
  report=json.loads((captures/stage/'transaction_audit.json').read_text('utf-8-sig'))
  require(report.get('accepted',report.get('raw_transactions_valid'))is True and report['firmware_id']=='26102801','supplementary audit did not accept')
  reports[stage]=dict(source=path.relative_to(root).as_posix(),source_sha256=sha(raw),transformed_sha256=sha(transformed.encode('utf-8')),replacement=dict(before=old,after='26102801',occurrences=count),result=report)
 (out/'summary.json').write_text(json.dumps(dict(accepted=True,stages=reports),indent=2)+'\n','utf-8');return reports
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--captures',type=Path);a=ap.parse_args()
 if a.captures:replay(a.repo.resolve(),a.captures.resolve(),a.output.resolve())
 else:prepare(a.repo.resolve(),a.output.resolve())
 print('TICKER HOST PROFILE '+('AUDIT PASS'if a.captures else'PREPARED'));return 0
if __name__=='__main__':raise SystemExit(main())
