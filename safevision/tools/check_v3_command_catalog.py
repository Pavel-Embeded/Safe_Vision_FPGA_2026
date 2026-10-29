
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
   if len(cases)!=15 or any(key!=value or text.count('NAME_'+key+':')!=1 for key,value in cases):raise ValueError('incomplete/mismatched control command cases')
   names.update(value for key,value in cases)
 top_text=(root/TOP).read_text(encoding='utf-8')
 bindings={name:int(value) for name,value in re.findall(r"localparam\[6:0\] B_QUERY_([A-Z]+)=7'd(\d+);",top_text)}
 if bindings:
  if len(bindings)!=26 or any(top_text.count('B_QUERY_'+name+':')!=1 for name in bindings if name!='DIAG') or top_text.count('cmd_catalog_id==B_QUERY_DIAG')!=1:raise ValueError('incomplete/duplicate board query consumer')
  names.update(bindings)
 if len(names)!=41:raise ValueError('board command vocabulary changed; review finite catalog and tests')
 extensions=['BRTPC','FIELD','LATENCY','MENU','SCALESEL']
 if not set(extensions)<=names:raise ValueError('missing handbook commands')
 ordered=sorted(names-set(extensions)-{'DIAG'})+['DIAG']+extensions;expected=bytearray(1024)
 controls=(root/'safevision/rtl/control/v3_user_controls.v').read_text(encoding='utf-8')
 control_ids={name:int(value) for name,value in re.findall(r"localparam\[6:0\] CTRL_ID_([A-Z]+)=7'd(\d+);",controls)}
 if control_ids:
  if len(control_ids)!=15 or any(value!=ordered.index(name)+1 or controls.count('CTRL_ID_'+name+':decode_catalog=OP_'+name+';')!=1 for name,value in control_ids.items()):raise ValueError('control catalog ID differs from exact name catalog')
  if not any(signature in top_text for signature in ['v3_user_controls #(.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) controls(', 'v3_user_controls #(.UI_TIMEBASE(1),.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) controls(', 'v3_user_controls #(.CLK_HZ(SYS_HZ),.DEBOUNCE(SYS_HZ/50),.UI_TIMEBASE(1),.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) controls(']) or '.catalog_id(cmd_catalog_id),.command_valid(cmd_valid && cmd_target!=66)' not in top_text:raise ValueError('board controls must consume the exact parser catalog ID')
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
 if not any(signature in top_text for signature in ('v3_uart_link #(.BOARD_CATALOG(1)) uart(', 'v3_uart_link #(.CLK_HZ(SYS_HZ),.BOARD_CATALOG(1)) uart(')):raise ValueError('board must opt into verified command catalog')


 if '.CLK_HZ(SYS_HZ)'in top_text:
  for marker in (
   'localparam integer SYS_HZ=HD?100000000:50000000;',
   'assign sys_clk=HD?pll_sys100_clk:mem_clk;',
   '.clk0_out(pll_sys100_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft));',
   'v3_user_controls #(.CLK_HZ(SYS_HZ),.DEBOUNCE(SYS_HZ/50),.UI_TIMEBASE(1),',
   'v3_supervisor #(.CLK_HZ(SYS_HZ),.FRAME_CYCLES(SYS_HZ/10),.MEM_CYCLES(SYS_HZ/5),.PROGRESS_CYCLES(SYS_HZ/2),.PROGRESSIVE_LOAD(1),',
   'localparam integer RECOVERY_CYCLES=SYS_HZ/10*49;',
   '.RECOVER_CYCLES(RECOVERY_CYCLES)',
   'v3_response_timer #(.CLK_HZ(SYS_HZ)) response_timer(',
   'v3_uart_link #(.CLK_HZ(SYS_HZ),.BOARD_CATALOG(1)) uart(',
  ):
   if top_text.count(marker)!=1:raise ValueError('incomplete/mismatched actual board control clock plan: '+marker)

 return {'accepted':True,'commands':ordered,'exact_rom_bytes':len(actual),'rom_sha256':hashlib.sha256(actual).hexdigest(),'minimum_uart_divider':32,'minimum_catalog_name_spacing_edges':84}

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);a=ap.parse_args();print(json.dumps(check(a.repo),indent=2))
