


from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
REFERENCE='25d311a25288d24072d11aee77b19f7bad53e4fa'
NEW_RTL={'safevision/rtl/storage/v3_fat_name_store.v','safevision/rtl/storage/v3_flexible_media_index.v','safevision/rtl/video/v3_audio_spectrum.v','safevision/rtl/video/v3_scrolling_ticker.v'}
NEW_HEADERLESS={'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/ticker_enable.v'}

def clean(text):
 return re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*[\s\S]*?\*/',lambda m:m.group(1)or' ',text)

def paren(text,start):
 assert text[start]=='(';depth=0;quote=False;escape=False
 for end in range(start,len(text)):
  c=text[end]
  if quote:
   if escape:escape=False
   elif c=='\\':escape=True
   elif c=='"':quote=False
   continue
  if c=='"':quote=True
  elif c=='(':depth+=1
  elif c==')':
   depth-=1
   if depth==0:return text[start+1:end],end+1
 raise ValueError('unclosed module header')

def headers(raw):
 text=clean(raw.decode('utf-8-sig'));result={}
 for m in re.finditer(r'\bmodule\s+([A-Za-z_][\w$]*)\s*',text):
  name=m.group(1);offset=m.end()
  if text[offset:offset+1]=='#':
   offset+=1
   while text[offset].isspace():offset+=1
   _,offset=paren(text,offset)
   while text[offset].isspace():offset+=1
  if text[offset:offset+1]!='(':continue
  ports,_=paren(text,offset);depth=0;start=0;items=[]
  for k,c in enumerate(ports+','):
   if c in '[(':depth+=1
   elif c in '])':depth-=1
   elif c==','and depth==0:
    item=ports[start:k].strip();start=k+1
    if item:
     p=re.search(r'([A-Za-z_][\w$]*)\s*(?:=[\s\S]*)?$',item)
     if not p:raise ValueError('unrecognized port declaration: '+item)
     items.append(p.group(1))
  if name in result:raise ValueError('duplicate module header: '+name)
  result[name]=items
 return result

def check(root,repository=None):
 root=Path(root).resolve();repository=Path(repository or root).resolve()
 if str(root/'safevision/tools')not in sys.path:sys.path.insert(0,str(root/'safevision/tools'))
 from v3_sources import snapshot
 physical=snapshot(root);records=[]
 for name in sorted(physical):
  if not name.endswith(('.v','.sv'))or name.endswith('.enc.v'):continue
  current=(root/name).read_bytes()
  if name in NEW_RTL:
   assert headers(current),'new RTL has no public module header: '+name
   continue
  if name in NEW_HEADERLESS:
   if headers(current):raise ValueError('macro-only input declares a module: '+name)
   records.append(dict(path=name,current_sha256=hashlib.sha256(current).hexdigest(),modules={},role='new macro-only input; no module ports'))
   continue
  p=subprocess.run(['git','-C',str(repository),'show',REFERENCE+':'+name],capture_output=True)
  if p.returncode:raise ValueError('missing historical interface blob: '+name)
  old=headers(p.stdout);new=headers(current)
  for module,ports in old.items():
   actual=new.get(module)
   if actual is None or actual[:len(ports)]!=ports:
    raise ValueError('legacy positional port order changed: '+name+' / '+module)
  records.append(dict(path=name,reference_sha256=hashlib.sha256(p.stdout).hexdigest(),current_sha256=hashlib.sha256(current).hexdigest(),modules={n:dict(legacy_port_count=len(p),appended_ports=new[n][len(p):])for n,p in old.items()}))
 return dict(accepted=True,scope='Original ordered module-port prefixes only; no simulation, STA, bitstream or hardware approval',reference_commit=REFERENCE,files=len(records),records=records)

def main():
 a=argparse.ArgumentParser(description=__doc__);a.add_argument('--repo',type=Path,default=ROOT);a.add_argument('--source-repo',type=Path);a.add_argument('--output',type=Path);v=a.parse_args()
 try:r=check(v.repo,v.source_repo);code=0
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e));code=1
 if v.output:v.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:x for k,x in r.items()if k!='records'}));return code
if __name__=='__main__':raise SystemExit(main())
