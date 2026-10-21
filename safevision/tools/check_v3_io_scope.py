"""Mapped asynchronous IO scope: real datapath bounds and an unused DDC DI."""
import re

def bounded_outputs(text,ports,budget=5.0,command='set_max_delay -datapath_only -to [get_ports {uart_txd led* HDMI_DDC_SCL}] 5.000'):
 groups=list(re.finditer(r'^Path Group\s*:\s*\n([^\n]+)\n\s*Type\s*:\s*SMD\s*$',text,re.M));found=[g for g in groups if ' '.join(g[1].split())==' '.join(command.split())]
 errors=[];paths=[]
 if len(found)!=1:return {'accepted':False,'errors':['missing/ambiguous exact asynchronous output bound'],'paths':[]}
 start=found[0].end();end=re.search(r'^Path Group\s*:',text[start:],re.M);section=text[start:start+end.start() if end else len(text)]
 pattern=re.compile(r'^Slack\s*:\s*([-+.0-9]+)ns\s*\nBegin Point\s*:\s*([^\n]*)\nEnd Point\s*:\s*([^\n]*)\nCheck Type\s*:\s*(\w+)\s*\nProcess\s*:\s*(slow|fast)\s*\nBudget\s*:\s*([-+.0-9]+)ns',re.M)
 for m in pattern.finditer(section):
  slack,begin,finish,kind,corner,actual=m.groups();finish=finish.split(' (')[0].strip()
  if finish not in ports:errors.append('unexpected bounded output '+finish)
  if kind!='setup' or abs(float(actual)-budget)>0.001:errors.append('wrong asynchronous output bound '+finish)
  if float(slack)<0:errors.append('negative asynchronous output flight '+finish)
  paths.append({'port':finish,'slack_ns':float(slack),'budget_ns':float(actual),'corner':corner})
 if set(p['port'] for p in paths)!=set(ports):errors.append('missing one or more actual asynchronous output path witnesses')
 return {'accepted':not errors,'errors':errors,'paths':paths,'scope':'physical propagation bound, no synchronous external receiver assumed'}

def dead_ddc_input(text):
 # The fixed-mode vendor EDID consumer is optimized out. Prove the resulting
 # exact physical PAD has no DI connection; no generic inout exemption exists.
 blocks=[]
 for m in re.finditer(r'EG_PHY_PAD\s*#\((.*?)\)\s+(\\[^\s]+|[\w$]+)\s*\((.*?)\);',text,re.S):
  if re.search(r'\.bpad\(\s*HDMI_DDC_SDA\s*\)',m[3]):blocks.append(m)
 errors=[]
 if len(blocks)!=1:return {'accepted':False,'errors':['missing/duplicated physical DDC SDA PAD']}
 m=blocks[0];params=dict(re.findall(r'^\s*\.(\w+)\(\s*"([^"\n]*)"\s*\)',m[1],re.M));pins=dict(re.findall(r'^\s*\.(\w+)\(([^\n]*)\)',m[3],re.M))
 if params.get('MODE')!='BI' or params.get('TO_DFFMODE')!='FF' or params.get('TSMUX')!='TS':errors.append('unexpected DDC SDA PAD mode')
 if 'di' in pins or 'ipad' in pins or 'ipclk' in pins:errors.append('DDC SDA receiver is live or receiver clock exists')
 if set(pins)!={'ce','do','osclk','rst','ts','bpad'}:errors.append('unexpected DDC SDA PAD pin set')
 if not re.fullmatch(r'\{open_n\d+,open_n\d+,open_n\d+,1\x27b0\}',pins.get('do','').strip()):errors.append('DDC SDA data is not constant open-drain zero')
 if pins.get('osclk','').strip()!='pixel_clk':errors.append('DDC SDA enable register lost PIX clock')
 for pin in ('ce','rst','ts'):
  if not pins.get(pin,'').strip().startswith('\\transmitter/u_hdmi_edid_wrapper/'):errors.append('unexpected vendor DDC '+pin+' source')
 return {'accepted':not errors,'errors':errors,'instance':m[2],'scope':'only absent DDC DI and constant-zero data; CE/TS/reset retain normal STA, external pull-up/load pending hardware'}
