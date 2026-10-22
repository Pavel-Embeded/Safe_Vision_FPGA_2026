"""Replay immutable qualification using only its minimal original Git objects."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,subprocess,tempfile,sys
sys.dont_write_bytecode=True
def verify(package):
 p=Path(package).resolve();j=json.loads((p/'release.index.json').read_text(encoding='utf-8-sig'));pack=p/'audit.gitobjects.pack'
 assert hashlib.sha256(pack.read_bytes()).hexdigest()==j['payload_sha256']['audit.gitobjects.pack']
 root=Path(tempfile.mkdtemp(prefix='svmedia_audit_'));store=root/'objects';source=p/'source'
 clean=os.environ.copy();keys=('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES')
 for key in keys:clean.pop(key,None)
 def git(*args,stdin=None):
  r=subprocess.run(['git',*args],env=clean,stdin=stdin,capture_output=True);assert r.returncode==0,r.stderr.decode(errors='replace');return r.stdout
 git('init','--quiet',str(store))
 with pack.open('rb')as f:git('-C',str(store),'index-pack','--stdin',stdin=f)
 git('-C',str(store),'config','core.worktree',str(source));git('-C',str(store),'config','core.autocrlf','false')
 git('-C',str(store),'update-ref','refs/heads/approved',j['approval_source_commit']);git('-C',str(store),'symbolic-ref','HEAD','refs/heads/approved')
 assert git('-C',str(store),'rev-parse',j['approval_source_commit']+'^{tree}')==git('-C',str(store),'rev-parse',j['publication_source_commit']+'^{tree}')
 saved={key:os.environ.get(key)for key in keys}
 try:
  for key in keys:os.environ.pop(key,None)
  os.environ['GIT_DIR']=str(store/'.git');os.environ['GIT_WORK_TREE']=str(source);os.environ['GIT_INDEX_FILE']=str(store/'audit.index')
  sys.path.insert(0,str(p))
  spec=importlib.util.spec_from_file_location('exact_media_payload_verifier',p/'verify_payload.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  result=m.verify(p,source);assert result['accepted'];return result
 finally:
  for key,value in saved.items():
   if value is None:os.environ.pop(key,None)
   else:os.environ[key]=value
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path);a=ap.parse_args();r=verify(Path(__file__).resolve().parent)
 if a.output:a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
 print('PORTABLE ORIGINAL OBJECTS / SOURCE /290 TOPS /205 CONTROLS /RAW STA /BIT VERIFIED',flush=True)
if __name__=='__main__':main()
