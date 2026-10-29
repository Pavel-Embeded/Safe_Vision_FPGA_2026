


import hashlib,json,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
IP=ROOT/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll'
def main():
 template=IP/'sv_board_memory_pll.v';text=template.read_text(encoding='utf-8')
 body=text[text.index('  EG_PHY_PLL #('):text.rindex('endmodule')]
 body=body.replace('sv_board_memory_pll','sv_v3_memory_pll').replace('.CLKC1_DIV(MEM_DIV)','.CLKC1_DIV(20)').replace('.CLKC1_CPHASE(MEM_CPH)','.CLKC1_CPHASE(19)').replace('.CLKC2_DIV(MEM_DIV)','.CLKC2_DIV(20)').replace('.CLKC2_CPHASE(SFT_CPH)','.CLKC2_CPHASE(7)')
 header='''// V3-only 50 MHz memory / +8 ns SDRAM profile. Legacy MEM40 is unchanged.
// Official TD EG_PHY_PLL template parameters: FIN50, REF1, FB2, C0DIV10 =>
// VCO1000 MHz; SYS100, MEM50 at 0deg, SDRAM50 at 144deg (=8 ns).
// Configured by tools/configure_v3_pll.py from the checked-in TD template.
// This is explicit template parameterization, not a claimed IPTool GUI run.
// Actual frequencies/phase must match native derive_clocks before release.
`timescale 1ns/100fs
module sv_v3_memory_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);
 wire clk0_buf,clk2_buf;
 wire sv_v3_memory_pll_open0,sv_v3_memory_pll_open1,sv_v3_memory_pll_open2,
 sv_v3_memory_pll_open3,sv_v3_memory_pll_open4,sv_v3_memory_pll_open5,
 sv_v3_memory_pll_open6,sv_v3_memory_pll_open7,sv_v3_memory_pll_open8,
 sv_v3_memory_pll_open10,sv_v3_memory_pll_open11;
 assign clk0_out=clk0_buf;
 EG_LOGIC_BUFG bufg_memory(.i(clk2_buf),.o(clk2_out));
'''
 (IP/'sv_v3_memory_pll.v').write_text(header+body+'endmodule\n',encoding='utf-8')
 tree=ET.parse(IP/'sv_system_pll.ipc');r=tree.getroot();r.find('Page3/setting').text='parameters_setting'
 for c in r.findall('Page3/clocks/clock'):
  i=int(c.findtext('id'));c.find('clock_division_factor').text='10' if i==0 else '20'
  c.find('clock_frequency').text='100.0000000000000000MHz' if i==0 else '50.0000000000000000MHz'
  c.find('phase_shift').text='144.0000000000000000deg' if i==2 else '0.0000000000000000deg'
 r.find('GeneratedFiles/Verilog').text='sv_v3_memory_pll.v';r.find('GeneratedFiles/VHDL').text='sv_v3_memory_pll.vhd'
 ET.indent(r,space='    ');tree.write(IP/'sv_v3_memory_pll.ipc',encoding='utf-8',xml_declaration=True)
 record={'schema':1,'configuration_method':'TD official primitive/template parameterization; IPTool automatic generation not claimed',
  'template_path':template.relative_to(ROOT).as_posix(),'template_sha256':hashlib.sha256(template.read_bytes()).hexdigest(),
  'system_hz':100000000,'memory_hz':50000000,'sdram_shift_ns':8,'vco_hz':1000000000,
  'basis':'50MHz shared-memory deadline proof; +10ns native SDRAM probe setup -0.565ns, +8ns probe setup +0.996ns/hold +0.023ns with unchanged IO budget. Full-board routed timing remains required.',
  'hardware_verified':False,'native_derived_clocks_verified':False}
 (IP/'sv_v3_memory_pll.provenance.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('Configured V3-only PLL; native derivation and vendor-model validation still required.')
if __name__=='__main__':main()
