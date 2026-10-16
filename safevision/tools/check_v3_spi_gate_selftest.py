"""Fault-inject strict native SPI, clock and asynchronous IO evidence parsers."""
import argparse,hashlib,json,re,sys
from pathlib import Path
from check_v3_spi_timing import check,check_cs
from check_v3_io_scope import bounded_outputs,dead_ddc_input
from check_v3_board import exception_timing,clock_definition_health
from v3_final_sta import timing_identity

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--native-probe',type=Path,required=True);ap.add_argument('--native-ddc-netlist',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 b=a.native_probe;timing=(b/'route.timing').read_text(encoding='utf-8-sig');exceptions=(b/'route.exceptions').read_text(encoding='utf-8-sig');health=(b/'route.check').read_text(encoding='utf-8-sig');ddc=a.native_ddc_netlist.read_text(encoding='utf-8-sig');cases=[]
 def test(name,condition):
  cases.append({'case':name,'pass':bool(condition)})
  if not condition:raise AssertionError(name)
 test('native SPI exact clocks/MCP/falling-edge capture paths',check(exceptions)['accepted'])
 test('ordinary CS has positive setup/hold in both SD modes',check_cs(timing)['accepted'])
 test('all native MCP/SMD paths zero failures',exception_timing(exceptions)['accepted'])
 test('pre-clock-report master and definition health exact zero',not clock_definition_health(health))
 test('post-clock diagnostic is rejected as formal health',bool(clock_definition_health((b/'after_clock_report.check').read_text(encoding='utf-8-sig'))))
 for name,text in [('missing master detail',re.sub(r'^2\.5[^\n]*','',health,flags=re.M)),('missing clock-definition count',health.replace('checking clock definition(0)','checking removed(0)')),('nonzero master connectivity',health.replace('There are 0 generated clocks','There are 1 generated clocks'))]:test(name,bool(clock_definition_health(text)))
 for name,text in [('wrong capture logical alias',exceptions.replace('/rx_sr[0]','/unrelated_register[0]')),('wrong physical MISO pad',exceptions.replace('sd_miso_syn_','unrelated_input_syn_')),('missing falling launch witness',exceptions.replace('falling edge triggered by clock sd_','rising edge triggered by clock sd_')),('wrong edge budget',exceptions.replace('Budget              : 40.000ns','Budget              : 39.000ns')),('CS included in MOSI MCP',exceptions.replace('get_ports {sd_mosi}] -to','get_ports {sd_mosi sd_ncs}] -to')),('truncated detailed paths',exceptions[:exceptions.index('Max Paths')]),('unrouted',exceptions.replace('Confidence          : Routed','Confidence          : Estimated'))]:test(name,not check(text)['accepted'])
 for name,text in [('CS wrong launch edge',timing.replace('falling edge triggered by clock board_clk','rising edge triggered by clock board_clk')),('CS ordinary budget corrupted',timing.replace('Budget              : 10.000ns','Budget              : 9.000ns'))]:test(name,not check_cs(text)['accepted'])
 # A negative SMD path is deliberately independent of the SPI MCP parser.
 m=re.search(r'^Slack\s*:\s*[-+.0-9]+ns\s*\nBegin Point\s*:\s*led\[',exceptions,re.M);test('native asynchronous LED SMD path exists',bool(m))
 bad=exceptions[:m.start()]+re.sub(r'^(Slack\s*:\s*)[-+.0-9]+ns',r'\g<1>-0.001ns',exceptions[m.start():],count=1)
 test('ordinary SMD negative path caught',not exception_timing(bad)['accepted'])
 test('truncated exception path caught',not exception_timing(exceptions+'\nSlack : 0.0ns\n')['accepted'])
 old=timing_identity(timing);new=timing_identity(re.sub(r'^(Slack\s*:\s*)([-+.0-9]+)ns',lambda m:m[1]+str(float(m[2])+0.001)+'ns',timing,count=1,flags=re.M));test('local slack mutation changes signature despite unchanged globals',old[0]==new[0] and old[1]!=new[1])
 ports=['led[0]','led[1]','led[2]','led[3]'];command='set_max_delay -datapath_only -to [get_ports {led*}] 5.000';bound=lambda s:bounded_outputs(s,ports,5.0,command)
 test('all four actual 5ns asynchronous LED paths bound',bound(exceptions)['accepted'])
 test('missing one bounded output caught',not bound(exceptions.replace('End Point           : led[0]','End Point           : unrelated_output'))['accepted'])
 test('incorrect asynchronous output budget caught',not bound(exceptions.replace('Budget              : 5.000ns','Budget              : 6.000ns'))['accepted'])
 test('negative asynchronous output caught',not bound(bad)['accepted'])
 test('native absent DDC DI is exactly proved',dead_ddc_input(ddc)['accepted'])
 m=next(m for m in re.finditer(r'EG_PHY_PAD\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\((.*?)\);',ddc,re.S) if '.bpad(HDMI_DDC_SDA)' in m[3]);block=m[0]
 for name,changed in [('live DDC receiver',block.replace('.bpad(HDMI_DDC_SDA)',".di(live_receiver),\n    .bpad(HDMI_DDC_SDA)")),('SDA nonzero data',block.replace("1'b0}","1'b1}")),('SDA enable lost PIX clock',block.replace('.osclk(pixel_clk)',".osclk(1'b0)")),('missing open-drain mode',block.replace('.TSMUX("TS")','.TSMUX("0")'))]:test(name,not dead_ddc_input(ddc[:m.start()]+changed+ddc[m.end():])['accepted'])
 test('duplicate physical SDA pad caught',not dead_ddc_input(ddc+'\n'+block)['accepted'])
 inputs=[b/'route.timing',b/'route.exceptions',b/'route.check',b/'after_clock_report.check',a.native_ddc_netlist]
 result={'complete':all(x['pass'] for x in cases),'cases':cases,'inputs':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},'scope':'checker fault injection and native diagnostic witnesses only; no full-board/hardware signoff'}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2),encoding='utf-8');print('PASS strict SPI/IO evidence selftest cases='+str(len(cases)));return 0
if __name__=='__main__':sys.exit(main())
