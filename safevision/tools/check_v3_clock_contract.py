"""Check configured nominal PLL counters against V3 board/HUD parameters.

This is not a PLL behavioral simulation or an oscillator measurement. The
NORMAL / CLKC0_EXT EG_PHY_PLL template has VCO = FIN * FB * C0DIV / REFDIV.
Native derive_clocks and routed STA remain separate required evidence.
"""
import argparse,hashlib,json,re
from fractions import Fraction
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]

def supervisor_parameters(text):
 """Read explicit named parameters without evaluating Verilog text."""
 headers=re.findall(r'\bv3_supervisor\s*#\((.*?)\)\s+supervisor\s*\(',text,re.S)
 if len(headers)!=1 or re.search(r'\bdefparam\s+supervisor\.',text):
  raise ValueError('missing/ambiguous supervisor instance or defparam override')
 header=re.sub(r'\s+','',headers[0])
 pairs=re.findall(r'\.([A-Za-z_][A-Za-z_0-9]*)\(([^()]*)\)',header)
 if ','.join('.'+key+'('+value+')'for key,value in pairs)!=header:
  raise ValueError('unsupported supervisor parameter syntax')
 if len({key for key,value in pairs})!=len(pairs):raise ValueError('duplicate supervisor parameter')
 values=dict(pairs)
 if not set(values)<={'RECOVER_CYCLES','WINDOW_PIPELINE','BOOT_MS_OVERRIDE','PROGRESSIVE_LOAD'} or not re.fullmatch(r'\d+',values.get('RECOVER_CYCLES','')):
  raise ValueError('unexpected or nonliteral supervisor recovery parameter')
 if 'BOOT_MS_OVERRIDE'in values and values['BOOT_MS_OVERRIDE']!='60000':
  raise ValueError('variable-resolution board load budget must be60000ms')
 if 'WINDOW_PIPELINE'in values and values['WINDOW_PIPELINE']!='HD':
  raise ValueError('window pipeline must explicitly follow the HD mode')
 if 'PROGRESSIVE_LOAD'in values and values['PROGRESSIVE_LOAD']!='1':
  raise ValueError('progressive media load must be explicitly enabled or omitted')
 return values


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
 # SPI25 is opt-in; the source, declared electrical profile and generated
 # clocks must agree before any physical build can be approved.
 budget_path=sdc.parent/'io_budget.json';sd=json.loads(budget_path.read_text(encoding='utf-8'))['sd']
 profile=sd.get('miso_sample_edge')=='falling_ref'
 if (t.count('.MID_REF_SAMPLE(1)')==1)!=profile:raise ValueError('SPI source and declared sampling profile disagree')
 if profile:
  if t.count('.MID_REF_SAMPLE(1)')!=1 or t.count('.CLK_DIV_FAST(0)')!=1 or t.count('.CLK_DIV_INIT(249)')!=1:
   raise ValueError('SPI25 board instantiation does not match falling-REF profile')
  spi_source=root/'safevision/rtl/storage/spi_master.v';spi_text=spi_source.read_text(encoding='utf-8')
  if 'generate if (MID_REF_SAMPLE)' not in spi_text or 'always @(negedge clk or negedge rst_n)' not in spi_text:
   raise ValueError('SPI25 actual receive process lost falling REF')
  player=root/'safevision/rtl/storage/sd_bmp_player.v'
  if player.read_text(encoding='utf-8').count('.MID_REF_SAMPLE(MID_REF_SAMPLE)')!=1:raise ValueError('SPI25 parameter is not forwarded')
  sdc_text=sdc.read_text(encoding='utf-8')
  for clock,divide in [('sd_fast',2),('sd_ident',500)]:
   rows=[x for x in sdc_text.splitlines()if x.startswith('create_generated_clock -name '+clock+' ')]
   if len(rows)!=1 or ('-divide_by '+str(divide)+' ')not in rows[0]:raise ValueError('wrong SPI generated clock '+clock)
  expected={'fast_clock_hz':25000000,'identification_clock_hz':100000,'fast_miso_input_max_ns':18,'identification_miso_input_max_ns':54,'miso_min_ns':0,'mosi_cs_output_max_ns':7,'mosi_cs_output_min_ns':-7,'receive_hold_budget_ns':10,'receive_hold_capture_offset_ns':-10}
  if any(sd.get(k)!=v for k,v in expected.items()):raise ValueError('SPI electrical contract differs from validated envelope')
  for clock,value in [('sd_fast',18),('sd_ident',54)]:
   for label in ['-max '+str(value)+'.000','-min 0.000']:
    if not any(line.startswith('set_input_delay -clock [get_clocks '+clock+'] -clock_fall '+label+' ')for line in sdc_text.splitlines()):raise ValueError('missing physical falling-SCLK input budget')
  for clock,n in [('sd_fast',2),('sd_ident',251)]:
   for cmd in ['set_multicycle_path -setup -from [get_clocks '+clock+'] -to [get_pins {sd_miso_syn_*.ipad}] '+str(n),
               'set_multicycle_path -hold -end -from [get_clocks '+clock+'] -to [get_pins {sd_miso_syn_*.ipad}] '+str(n-1)]:
    if sdc_text.splitlines().count(cmd)!=1:raise ValueError('SPI literal receive-enable constraint differs')
  mp=ip/'sv_v3_memory_pll.v';mt=mp.read_text(encoding='utf-8')
  if Fraction(re.search(r'\.FIN\("([\d.]+)"\)',mt)[1])*1000000!=ref_hz:raise ValueError('memory PLL FIN differs from board reference')
  vals={k:int(re.search(r'\.'+k+r'\((\d+)\)',mt)[1])for k in ['REFCLK_DIV','FBCLK_DIV']}
  sys_hz=ref_hz*vals['FBCLK_DIV']/vals['REFCLK_DIV']
  supervisor=supervisor_parameters(t)
  recovery_cycles=int(supervisor['RECOVER_CYCLES'])
  if recovery_cycles!=sys_hz*49/10 or (recovery_cycles+130)>=sys_hz*5:raise ValueError('recovery wait/reset/settle deadline exceeds5s envelope')
  spi_profile={'enabled':True,'fast_hz':25000000,'sample_edge':'falling_REF','hold_budget_ns':10,'native_edges_separately_required':True,'recovery_wait_seconds':float(Fraction(recovery_cycles,sys_hz)),'electrical_contract_sha256':hashlib.sha256(budget_path.read_bytes()).hexdigest()}
  progressive=supervisor.get('PROGRESSIVE_LOAD')=='1'
  if progressive:
   if t.count('.FLEX_FILES(1)')!=1:raise ValueError('progressive load requires the bounded flexible media loader')
   for mode in ('control','hd'):
    raw=(root/f'safevision/rtl/{mode}/v3_supervisor.v').read_text(encoding='utf-8')
    if raw.count('.PROGRESSIVE_WAIT(PROGRESSIVE_LOAD)')!=1 or raw.count('.progress(progress_heartbeat || mem_heartbeat)')!=1:
     raise ValueError('progressive recovery heartbeat is not propagated: '+mode)
  spi_profile.update(recovery_budget_kind='no_progress'if progressive else'total_wait',
    boot_budget_kind='no_progress'if progressive else'total_preload',
    total_recovery_duration_bounded_by_this_check=not progressive)
 else:spi_profile={'enabled':False,'profile':'legacy','native_edges_separately_required':True}
 return {'complete':True,'kind':'configured_nominal_clock_contract','clocks':clocks,'spi_profile':spi_profile,'board_reference_hz':float(ref_hz),
  'board_sdc_sha256':hashlib.sha256(sdc.read_bytes()).hexdigest(),
  'board_sha256':hashlib.sha256(top.read_bytes()).hexdigest(),'core_sha256':hashlib.sha256(core.read_bytes()).hexdigest(),
  'native_derived_clocks_verified_by_this_check':False,'hardware_verified':False}

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--output',type=Path)
 a=ap.parse_args();result=check(a.repo.resolve());text=json.dumps(result,indent=2)
 if a.output:a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(text+'\n',encoding='utf-8',newline='\n')
 print(text)

if __name__=='__main__':main()
