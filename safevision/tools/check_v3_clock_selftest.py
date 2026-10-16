"""Reject nominal PLL/counter/SDC drift; this does not sign off physical clocks."""
import argparse,json,shutil,tempfile
from pathlib import Path
from check_v3_clock_contract import ROOT,check

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 base='safevision/platform/anlogic_eg4s20_hx4s20c/'
 files=[base+'ip/pll/'+n for n in ['sv_video_hd_pll.v','sv_video_vga_pll.v']]+[base+'rtl/safevision_top/safevision_v3_top.v','safevision/rtl/video/v3_video_display_core.v',base+'project/v3_board_verify/v3_board.sdc']
 controls=[('positive',None,None,None),
  ('hd_pll_drift',files[0],'.CLKC1_DIV(15)','.CLKC1_DIV(16)'),
  ('base_counter_drift',files[2],'HD?74166667:25185185','HD?74166667:25175000'),
  ('missing_core_link',files[3],'.PIXEL_HZ(PIXEL_HZ)','.PIXEL_HZ(25175000)'),
  ('input_constraint_drift',files[4],'-period 20.000','-period 20.100'),
  ('feedback_mode_drift',files[0],'.FEEDBK_MODE("NORMAL")','.FEEDBK_MODE("OTHER")')]
 rows=[];scratch_parent=a.output.parent.resolve();scratch_parent.mkdir(parents=True,exist_ok=True)
 # Use the requested output directory to avoid the long Windows sandbox TEMP
 # prefix. Verify the generated cleanup target remains below that directory.
 with tempfile.TemporaryDirectory(prefix='clocks_',dir=scratch_parent) as temp:
  if not Path(temp).resolve().is_relative_to(scratch_parent):raise ValueError('Temporary directory escaped output')
  for label,name,old,new in controls:
   root=Path(temp)/label
   for n in files:
    p=root/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/n,p)
   if name:
    p=root/name;text=p.read_text(encoding='utf-8')
    if text.count(old)!=1:raise ValueError('Negative fixture is no longer applicable: '+label)
    p.write_text(text.replace(old,new),encoding='utf-8',newline='\n')
   error=None
   try:check(root)
   except ValueError as ex:error=str(ex)
   if (error is None)!=(name is None):raise AssertionError((label,error))
   rows.append({'case':label,'expected_negative':name is not None,'detected':error is not None,'error':error})
 result={'complete':True,'results':rows,'native_clock_verification':False,'hardware_verified':False}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
 print('PASS nominal clock checker controls=6 expected_rejections=5')

if __name__=='__main__':main()
