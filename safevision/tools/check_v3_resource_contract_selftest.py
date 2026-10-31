
import argparse,copy,json,tempfile
from pathlib import Path
from v3_sources import ROOT,FLOW,native_parameters
from v3_resource_policy import load,validate
from check_v3_board import resource_gate
from check_v3_board_reference import check as board_check
from check_v3_command_catalog import check as catalog_check

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();cases=[]
 def ck(name,ok):
  cases.append({'case':name,'pass':bool(ok)})
  if not ok:raise AssertionError(name)
 def rejects(fn):
  try:fn();return False
  except (ValueError,FileNotFoundError):return True
 policy=load(ROOT)
 area='\n'.join('#%s %d out of %d 0.00%%'%x for x in [('lut',17010,19600),('reg',13125,19600),('bram',51,64),('bram32k',0,16),('dsp',26,29),('pll',3,4)])
 ck('approved 86.8 percent LUT passes area only',resource_gate(area,policy)['accepted'])
 ck('legacy policy retained separately',not resource_gate(area)['accepted'])
 for name,old,new in [('lut',17010,19601),('reg',13125,15681),('bram',51,65),('bram32k',0,4),('dsp',26,30),('pll',3,2)]:
  ck('reject '+name+' limit violation',not resource_gate(area.replace('#%s %d '%(name,old),'#%s %d '%(name,new)),policy)['accepted'])
 ck('reject spoofed report device capacity',not resource_gate(area.replace('out of  19600','out of  30000').replace('out of 19600','out of 30000'),policy)['accepted'])
 for key,value in [('physical_capacity',{'lut':30000}),('hard_caps_percent',{'lut':101,'reg':80,'ram':85}),('requires_all_corner_setup_hold_recovery_removal',False),('requires_successful_native_placement_routing',False),('feature_reduction_permitted',True)]:
  p=copy.deepcopy(policy);p[key]=value;ck('reject policy corruption '+key,rejects(lambda:validate(p)))
 ck('independent board ADC baseline',board_check(ROOT)['accepted']);ck('complete exact command baseline',catalog_check(ROOT)['accepted'])
 a.output=a.output.resolve();a.output.parent.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='sv_contract_',dir=a.output.parent) as d:
  root=Path(d)
  names=[FLOW/'board_reference.json',FLOW/'v3_board.adc',FLOW/'v3_board.sdc',FLOW/'v3_build_parameters.tcl',Path('safevision/rtl/control/v3_user_controls.v'),Path('safevision/rtl/control/v3_command_parser_catalog.v'),Path('safevision/assets/control/v3_command_catalog.mem'),Path('safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v')]
  for n in names:
   p=root/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/n).read_bytes())
  adc=root/FLOW/'v3_board.adc';orig=adc.read_bytes();adc.write_bytes(orig.replace(b'LOCATION = G5',b'LOCATION = N5'))
  ck('reject HDMI A/B pin substitution',rejects(lambda:board_check(root)));adc.write_bytes(orig)
  rom=root/'safevision/assets/control/v3_command_catalog.mem';orig=rom.read_bytes();rom.write_bytes(b'40'+orig[2:])
  ck('reject command ROM corruption',rejects(lambda:catalog_check(root)));rom.write_bytes(orig)
  controls=root/'safevision/rtl/control/v3_user_controls.v';original_controls=controls.read_bytes();top=root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v';original_top=top.read_bytes()
  controls.write_bytes(original_controls.replace(b"CTRL_ID_BRIGHT=7'd5;",b"CTRL_ID_BRIGHT=7'd127;"));ck('reject incorrect control catalog ID',rejects(lambda:catalog_check(root)));controls.write_bytes(original_controls)
  control_mode=b'.UI_TIMEBASE(1),.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1)'
  assert original_top.count(control_mode)==1
  top.write_bytes(original_top.replace(control_mode,b'.UI_TIMEBASE(1),.BOARD_CATALOG(0),.SYSTEM_SAFE_ENABLE(1)'));ck('reject lost board control catalog mode',rejects(lambda:catalog_check(root)));top.write_bytes(original_top)
  assert original_top.count(b'.catalog_id(cmd_catalog_id),.command_valid(cmd_valid && cmd_target!=66)')==1
  top.write_bytes(original_top.replace(b'.catalog_id(cmd_catalog_id),.command_valid(cmd_valid && cmd_target!=66)',b".catalog_id(7'd0),.command_valid(cmd_valid && cmd_target!=66)"));ck('reject lost board control ID connection',rejects(lambda:catalog_check(root)));top.write_bytes(original_top)
  controls.write_text(controls.read_text(encoding='utf-8')+'\n// command_name=="NEWCOMMAND"\n',encoding='utf-8')
  ck('detect future command absent from finite catalog',rejects(lambda:catalog_check(root)))
  ck('reject missing actual tool parameter tables',rejects(lambda:native_parameters(ROOT,root)))
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps({'complete':True,'scope':'release-contract parser negative controls only','cases':cases},indent=2),encoding='utf-8')
 print('PASS resource/board/catalog contract controls='+str(len(cases)))
if __name__=='__main__':main()
