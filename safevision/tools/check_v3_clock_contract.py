"""Check configured nominal PLL counters against V3 board/HUD parameters.

This is not a PLL behavioral simulation or an oscillator measurement. The
NORMAL / CLKC0_EXT EG_PHY_PLL template has VCO = FIN * FB * C0DIV / REFDIV.
Native derive_clocks and routed STA remain separate required evidence.
"""
import argparse,hashlib,json,re
from fractions import Fraction
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]

def check(root):
 ip=root/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll'
 sdc=root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board.sdc'
 clock=re.search(r'^create_clock -name board_clk -period ([\d.]+) -waveform \{0 10\} \[get_ports \{clk\}\]$',sdc.read_text(encoding='utf-8'),re.M)
 if not clock:raise ValueError('Missing supported board input clock constraint')
 ref_hz=Fraction(1000000000)/Fraction(clock[1])
 clocks={}
 for mode,name in [('base','sv_video_vga_pll.v'),('hd','sv_video_hd_pll.v')]:
  p=ip/name;t=p.read_text(encoding='utf-8')
  if '.FEEDBK_MODE("NORMAL")' not in t or '.FEEDBK_PATH("CLKC0_EXT")' not in t:
   raise ValueError('Unsupported PLL feedback configuration: '+name)
  values={k:int(re.search(r'\.'+k+r'\((\d+)\)',t)[1]) for k in ['REFCLK_DIV','FBCLK_DIV','CLKC0_DIV','CLKC1_DIV','CLKC2_DIV']}
  if any(v<1 for v in values.values()):raise ValueError('PLL divider must be positive')
  fin=Fraction(re.search(r'\.FIN\("([\d.]+)"\)',t)[1])*1000000
  if fin!=ref_hz:raise ValueError('PLL input frequency differs from board SDC: '+name)
  pixel=fin*values['FBCLK_DIV']*values['CLKC0_DIV']/(values['REFCLK_DIV']*values['CLKC1_DIV'])
  serial=fin*values['FBCLK_DIV']*values['CLKC0_DIV']/(values['REFCLK_DIV']*values['CLKC2_DIV'])
  if serial!=pixel*5:raise ValueError('TMDS serial/pixel nominal ratio is not five')
  clocks[mode]={'source':p.relative_to(root).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
   'pixel_hz_numerator':pixel.numerator,'pixel_hz_denominator':pixel.denominator,
   'nominal_pixel_hz':float(pixel),'rounded_counter_hz':round(pixel),'nominal_serial_hz':float(serial),'parameters':values}
 top=root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v';t=top.read_text(encoding='utf-8')
 m=re.search(r'localparam\s+integer\s+PIXEL_HZ\s*=\s*HD\s*\?\s*(\d+)\s*:\s*(\d+)\s*;',t)
 if not m or int(m[1])!=clocks['hd']['rounded_counter_hz'] or int(m[2])!=clocks['base']['rounded_counter_hz']:
  raise ValueError('Board HUD counter frequency differs from official PLL nominal counters')
 core=root/'safevision/rtl/video/v3_video_display_core.v'
 for p in [top,core]:
  if p.read_text(encoding='utf-8').count('.PIXEL_HZ(PIXEL_HZ)')!=1:raise ValueError('Clock parameter is not propagated once: '+str(p))
 return {'complete':True,'kind':'configured_nominal_clock_contract','clocks':clocks,'board_reference_hz':float(ref_hz),
  'board_sdc_sha256':hashlib.sha256(sdc.read_bytes()).hexdigest(),
  'board_sha256':hashlib.sha256(top.read_bytes()).hexdigest(),'core_sha256':hashlib.sha256(core.read_bytes()).hexdigest(),
  'native_derived_clocks_verified_by_this_check':False,'hardware_verified':False}

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--output',type=Path)
 a=ap.parse_args();result=check(a.repo.resolve());text=json.dumps(result,indent=2)
 if a.output:a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(text+'\n',encoding='utf-8',newline='\n')
 print(text)

if __name__=='__main__':main()
