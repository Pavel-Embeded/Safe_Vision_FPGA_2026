"""Replay the full original routed checker at recorded Windows paths.

Only published bytes are restored. This command never invokes TD, a download
tool or a serial port. Existing source/report directories are never overwritten.
"""
import argparse,hashlib,json,os,re,shutil,subprocess,sys
from pathlib import Path,PureWindowsPath,PurePosixPath
from check_v3_board import check
from run_v3_board import source_commit_binding
from v3_sources import snapshot
PREFIX=Path('D:/Codex/sv_scroll261028')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise ValueError(message)
def read(p):return json.loads(p.read_text('utf-8-sig'))
def replay(root,native):
 require(os.name=='nt','recorded native path replay requires Windows')
 root=root.resolve();record=read(native/'base/build.manifest.json')
 hardware=snapshot(root);require(record['status']=='PASS'and record['source_unchanged']and record['sources']==hardware,'current production differs from accepted native inputs')
 require(record['source_commit_binding']['verified'],'native build has no source binding')
 binding=source_commit_binding(root,root,record['source_commit'],hardware);require(binding['verified'],'build commit does not bind current bytes')
 source=Path(record['source_commit_binding']['source_repository'])
 require(source.parent==PREFIX and re.fullmatch(r'(?:[a-z0-9_]{1,24}_source|source)',source.name),'unapproved source restoration path')
 databases=[Path(row['path'])for row in record['gate']['reports']if PureWindowsPath(row['path']).name=='route.db']
 require(len(databases)==1,'missing unique native database identity')
 folder=databases[0].parent;run=folder.parent
 require(folder.name=='base'and run.parent==PREFIX and re.fullmatch('native[0-9]{2}',run.name),'unapproved native restoration path')
 created=[];owned={}
 def validate_directory(path):
  require(path.resolve().is_relative_to(PREFIX.resolve()),'restored path escaped workspace')
  for p in [path,*path.parents]:
   require(not p.is_symlink()and not(getattr(p,'is_junction',lambda:False)()),'restoration through reparse path')
   if p==PREFIX:break
 def restore(directory,files):
  validate_directory(directory)
  if directory.exists():
   require(all((directory/n).is_file()and sha(directory/n)==sha(p)for n,p in files.items()),'existing recorded directory differs; nothing overwritten: '+str(directory))
   return
  directory.mkdir(parents=True);created.append(directory);expected={}
  for name,path in files.items():
   rel=PurePosixPath(name);require(not rel.is_absolute()and'..'not in rel.parts and':'not in name,'unsafe restored file')
   dest=directory.joinpath(*rel.parts);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,dest);expected[name]=sha(dest)
  owned[directory]=expected
 try:
  restore(source,{name:root/name for name in hardware})
  files={p.relative_to(native).as_posix():p for p in native.rglob('*')if p.is_file()}
  require(files,'native evidence folder is empty');restore(run,files)
  if source in owned and (root/'safevision/tools/v3_checkpoint_flow.py').is_file():
   # The new flow guard reconstructs tools from a frozen parent Git blob.
   # A fresh physical-input restoration therefore needs read access to that
   # existing object store. This plain metadata file changes no Git refs,
   # checkout or index, and is deleted only with the directory created here.
   gitdir=Path(subprocess.check_output(['git','-C',str(root),'rev-parse','--absolute-git-dir']).decode('utf-8').strip()).resolve()
   require(gitdir.is_dir(),'frozen parent object store is unavailable')
   marker=source/'.git';require(not marker.exists(),'existing Git metadata is never overwritten')
   marker.write_text('gitdir: '+gitdir.as_posix()+'\n',encoding='utf-8',newline='\n')
   owned[source]['.git']=sha(marker)
  require(snapshot(source)==hardware,'restored physical input closure differs')
  for report in record['gate']['reports']:
   original=Path(report['path']);require(original.parent==folder and sha(original)==report['sha256'],'approved native report/database changed')
  actual=check(folder,source)
  require(actual['status']=='PASS'and actual['gate_accepted']and actual['timing_passed'],'full routed replay failed: '+str(actual['errors']))
  return dict(accepted=True,fresh_TD_build_performed=False,hardware_test_performed=False,full_native_gate_replayed=True,gate=actual,source_commit_binding=binding)
 finally:
  # Remove only directories made here, and only while every restored byte is
  # still exactly ours. Unexpected files or edits leave the directory intact.
  for directory in reversed(created):
   validate_directory(directory);expected=owned.get(directory,{})
   actual={p.relative_to(directory).as_posix():sha(p)for p in directory.rglob('*')if p.is_file()}
   require(actual==expected,'restored directory changed during replay; cleanup refused')
   shutil.rmtree(directory)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--native',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=replay(a.repo,a.native)
 except Exception as exc:r=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('TICKER FULL NATIVE REPLAY '+('PASS'if r['accepted']else'FAILED: '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':sys.exit(main())
