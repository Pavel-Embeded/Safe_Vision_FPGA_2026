"""Compare all 3072 graphics/command ROM bytes with mapped initialization bits."""
import argparse,hashlib,json,re,sys
from pathlib import Path
def check_roms(text,root):
 mapped=[]
 for m in re.finditer(r'EG_PHY_BRAM\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\(',text,re.S):
  if not any(prefix in m[2] for prefix in ('video/graphics/','uart/g_catalog/parser/','uart/g_catalog$parser/')):continue
  blocks={int(k,16):int(v,16).to_bytes(32,'little') for k,v in re.findall(r'\.INIT_([0-9A-Fa-f]{2})\(256\s*\x27h([0-9A-Fa-f]{64})\)',m[1])}
  if set(blocks)==set(range(32)):mapped.append((m[2],b''.join(blocks[i] for i in range(32))))
 result=[]
 for rel in ('fonts/font8x16_compact.mem','fonts/v3_status_text.mem','control/v3_command_catalog.mem'):
  path=root/'safevision/assets'/rel;name=path.name
  tokens=path.read_text(encoding='utf-8-sig').split()
  expected=bytes(int(token,16) for token in tokens)
  if len(expected)!=1024:raise ValueError('ROM length is not 1024 bytes: '+name)
  matches=[n for n,data in mapped if data==expected]
  if len(matches)!=1:raise ValueError('mapped ROM content missing/corrupt/duplicated: '+name)
  result.append({'asset':name,'mapped_instance':matches[0],'bytes_compared':1024,'payload_sha256':hashlib.sha256(expected).hexdigest()})
 return result
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--netlist',type=Path,required=True);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:result={'accepted':True,'roms':check_roms(a.netlist.read_text(encoding='utf-8-sig'),a.repo)}
 except Exception as ex:result={'accepted':False,'error':str(ex)}
 a.output.write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2));return 0 if result['accepted'] else 1
if __name__=='__main__':sys.exit(main())
