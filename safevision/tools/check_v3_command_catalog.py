"""Fail if any board command, decoder literal or exact ROM byte is omitted."""
import argparse,hashlib,json,re
from pathlib import Path
from v3_sources import ROOT
TOP='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'

def check(root):
 names=set()
 for rel,var in [(TOP,'cmd_name'),('safevision/rtl/control/v3_user_controls.v','command_name')]:
  text=(root/rel).read_text(encoding='utf-8')
  names.update(re.findall(r'\b'+var+r'\s*==\s*"([A-Z]+)"',text))
  cases=re.findall(r'localparam\[95:0\] NAME_([A-Z]+)="([A-Z]+)";',text)
  if cases:
   if len(cases)!=11 or any(key!=value or text.count('NAME_'+key+':')!=1 for key,value in cases):raise ValueError('incomplete/mismatched control command cases')
   names.update(value for key,value in cases)
 top_text=(root/TOP).read_text(encoding='utf-8')
 bindings={name:int(value) for name,value in re.findall(r"localparam\[6:0\] B_QUERY_([A-Z]+)=7'd(\d+);",top_text)}
 if bindings:
  if len(bindings)!=24 or any(top_text.count('B_QUERY_'+name+':')!=1 for name in bindings):raise ValueError('incomplete/duplicate board query consumer')
  names.update(bindings)
 if len(names)!=35:raise ValueError('board command vocabulary changed; review finite catalog and tests')
 ordered=sorted(names);expected=bytearray(1024)
 if bindings and any(value!=ordered.index(name)+1 for name,value in bindings.items()):raise ValueError('board numeric query ID differs from exact name catalog')
 for index,name in enumerate(ordered):
  if not 1<=len(name)<=12:raise ValueError('invalid command length')
  data=name.encode('ascii')
  for pos,char in enumerate(data):expected[index*16+pos]=char|(128 if pos==len(data)-1 else 0)
 rom=root/'safevision/assets/control/v3_command_catalog.mem'
 actual=bytes(int(v,16) for v in rom.read_text().split())
 if actual!=expected:raise ValueError('command ROM differs from all board consumer literals')
 parser=(root/'safevision/rtl/control/v3_command_parser_catalog.v').read_text()
 decoded={int(i):bytes.fromhex(v).lstrip(b'\0').decode('ascii') for i,v in re.findall(r"7'd(\d+):catalog_name=96'h([0-9a-fA-F]{24})",parser)}
 if decoded!=dict(enumerate(ordered,1)):raise ValueError('catalog output decoder differs from ROM/consumers')
 if 'v3_uart_link #(.BOARD_CATALOG(1)) uart(' not in (root/TOP).read_text():raise ValueError('board must opt into verified command catalog')
 return {'accepted':True,'commands':ordered,'exact_rom_bytes':len(actual),'rom_sha256':hashlib.sha256(actual).hexdigest(),'minimum_uart_divider':32,'minimum_catalog_name_spacing_edges':72}

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);a=ap.parse_args();print(json.dumps(check(a.repo),indent=2))
