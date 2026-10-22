"""Same native Git blob comparison, batching files in their actual worktree."""
from pathlib import Path
import subprocess,re
def source_commit_binding(root,source_repo,ref,paths):
 root=Path(root).resolve();repo=Path(source_repo).resolve()
 if root!=repo:raise ValueError('Batch binding requires the actual source worktree')
 def git(*args,**kw):return subprocess.run(['git','-C',str(repo),*args],capture_output=True,**kw)
 p=git('rev-parse',ref+'^{commit}')
 if p.returncode:return dict(verified=False,commit=None,reason='source Git commit is unavailable')
 commit=p.stdout.decode('ascii').strip();p=git('ls-tree','-rz',commit)
 if p.returncode:return dict(verified=False,commit=commit,reason='source Git tree is unavailable')
 blobs={}
 for row in p.stdout.split(b'\0'):
  if row:
   meta,name=row.split(b'\t',1);fields=meta.split()
   if fields[1]==b'blob':blobs[name.decode('utf-8')]=fields[2].decode('ascii')
 names=list(paths);errors=[]
 for name in names:
  q=(root/name).resolve()
  if not q.is_relative_to(root)or '\n'in name or '\0'in name:raise ValueError('Unsafe binding input')
  if name not in blobs:errors.append('uncommitted build dependency: '+name)
 # Git applies each path's real .gitattributes; no Python reimplementation of
 # clean filters and no --no-filters shortcut. Relative file paths and -C are
 # identical to the original hash-object --stdin --path invocation.
 p=git('hash-object','--stdin-paths',input=('\n'.join(names)+'\n').encode('utf-8'))
 hashes=p.stdout.decode('ascii').splitlines()
 if p.returncode or len(hashes)!=len(names):raise ValueError('Native Git batch hash did not complete')
 for name,digest in zip(names,hashes):
  if not re.fullmatch('[0-9a-f]{40}',digest)or blobs.get(name)!=digest:errors.append('build bytes differ from source commit: '+name)
 # Independently exercise the original primitive on representative positions,
 # raw CRLF transcripts, memory images and the new CRLF manifest.
 probes=set(names[::max(1,len(names)//8)])
 for suffix in('directory_alias510_sim.json','.mem','.pdf','sim.log'):
  hit=next((name for name in names if name.endswith(suffix)),None)
  if hit:probes.add(hit)
 by_name=dict(zip(names,hashes))
 for name in sorted(probes):
  p=git('hash-object','--stdin','--path='+name,input=(root/name).read_bytes())
  if p.returncode or p.stdout.decode('ascii').strip()!=by_name[name]:raise ValueError('Batch differs from original native Git primitive: '+name)
 return dict(verified=not errors,commit=commit,source_repository=str(repo),dependencies_compared=len(names),errors=errors,binding_method='native_git_per_path_filters_batched',original_primitive_probes=len(probes))
