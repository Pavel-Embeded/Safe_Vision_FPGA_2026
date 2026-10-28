"""Content-addressed storage for native logs, fixtures and timing evidence."""
import argparse,hashlib,json,os,zipfile
from pathlib import Path,PurePosixPath
SKIP_DIRS={'xsim.dir','.Xil','tmp','__pycache__'}
SKIP_SUFFIX={'.wdb','.pb','.jou','.wcfg'}
def sha(data):return hashlib.sha256(data).hexdigest()
def member(name):
 p=PurePosixPath(name)
 if not name or p.is_absolute()or'..'in p.parts or':'in name or'\\'in name:raise ValueError('unsafe archive name: '+name)
 return p
def pack(groups,output):
 if output.exists():raise ValueError('fresh archive required')
 entries={};objects=set()
 with zipfile.ZipFile(output,'x',zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True)as z:
  for label,root in groups.items():
   member(label)
   for folder,dirs,files in os.walk(root):
    dirs[:]=sorted(d for d in dirs if d not in SKIP_DIRS)
    for name in sorted(files):
     path=Path(folder)/name
     if path.suffix.lower()in SKIP_SUFFIX:continue
     if path.is_symlink():raise ValueError('source link in evidence')
     logical=label+'/'+path.relative_to(root).as_posix();member(logical)
     raw=path.read_bytes();digest=sha(raw)
     if digest not in objects:z.writestr('objects/'+digest,raw);objects.add(digest)
     if logical in entries:raise ValueError('duplicate logical evidence')
     entries[logical]=dict(sha256=digest,bytes=len(raw))
  index=dict(schema=1,entries=entries,objects=len(objects),logical_files=len(entries),logical_bytes=sum(e['bytes']for e in entries.values()))
  z.writestr('index.json',json.dumps(index,sort_keys=True,indent=2)+'\n')
 return index
def unpack(archive,output):
 if output.exists():raise ValueError('fresh extraction directory required')
 with zipfile.ZipFile(archive)as z:
  names=z.namelist()
  if len(names)!=len(set(names)):raise ValueError('duplicate archive member')
  index=json.loads(z.read('index.json'));entries=index['entries']
  expected={'index.json'}|{'objects/'+row['sha256']for row in entries.values()}
  if set(names)!=expected:raise ValueError('missing or unlisted archive objects')
  verified={}
  for logical,row in entries.items():
   member(logical);digest=row['sha256']
   if len(digest)!=64 or any(c not in'0123456789abcdef'for c in digest):raise ValueError('invalid object digest')
   verified.setdefault(digest,[]).append((logical,row['bytes']))
  if index['objects']!=len(verified)or index['logical_files']!=len(entries)or index['logical_bytes']!=sum(e['bytes']for e in entries.values()):raise ValueError('archive inventory changed')
  output.mkdir(parents=True)
  for digest,targets in verified.items():
   data=z.read('objects/'+digest)
   if sha(data)!=digest:raise ValueError('corrupted archive object')
   for logical,size in targets:
    if len(data)!=size:raise ValueError('incorrect evidence byte count')
    p=output.joinpath(*member(logical).parts)
    if not p.resolve().is_relative_to(output.resolve()):raise ValueError('extraction escaped directory')
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 return index
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--archive',type=Path);ap.add_argument('--group',action='append',default=[]);a=ap.parse_args()
 if a.archive:r=unpack(a.archive,a.output)
 else:r=pack({name:Path(path)for name,path in(item.split('=',1)for item in a.group)},a.output)
 print(json.dumps({k:v for k,v in r.items()if k!='entries'},indent=2))
if __name__=='__main__':main()
