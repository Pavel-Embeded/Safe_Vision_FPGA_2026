
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FLOW=Path('safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify')
BASE_MEDIA_BRAM_LOCATIONS=(('player/normalized_bmp$u_unpack/ramread0_syn_5', 'X8Y18Z0'), ('player/normalized_bmp$u_unpack/ramread0_syn_15', 'X8Y18Z1'), ('row_guard/ramread0_syn_6', 'X8Y9Z0'), ('row_guard/ramread0_syn_23', 'X8Y9Z1'), ('sink/u_fifo/fifo/ram_inst/ramread0_syn_6', 'X8Y18Z3'), ('sink/u_fifo/fifo/ram_inst/ramread0_syn_16', 'X8Y18Z2'))
BASE_SHARED_BRAM_LOCATIONS=(('adapter/ramread0_syn_25', 'X8Y27Z2'), ('adapter/ramread0_syn_6', 'X8Y27Z3'), ('audio/hdmi_samples/q/u_fifo/ram_inst/ramread0_syn_6', 'X24Y9Z1'), ('audio/ingress_shared/q/u_fifo/ram_inst/ramread0_syn_6', 'X24Y18Z3'), ('audio/samples/q/u_fifo/ram_inst/ramread0_syn_16', 'X8Y27Z0'), ('audio/samples/q/u_fifo/ram_inst/ramread0_syn_6', 'X8Y27Z1'), ('audio/source/context_ram/ramread0_syn_6', 'X24Y9Z3'), ('player/checked_reader$u_rd/ramread0_syn_6', 'X32Y18Z1'), ('player/flexible_index$u_idx/ramread0_syn_6', 'X32Y18Z0'), ('player/normalized_bmp$u_unpack/ramread0_syn_15', 'X8Y18Z1'), ('player/normalized_bmp$u_unpack/ramread0_syn_5', 'X8Y18Z0'), ('player/shared_service$service/ds/full_names$names/ramread0_syn_6', 'X24Y9Z2'), ('row_guard/ramread0_syn_23', 'X8Y9Z1'), ('row_guard/ramread0_syn_6', 'X8Y9Z0'), ('sink/u_fifo/fifo/ram_inst/ramread0_syn_16', 'X8Y18Z2'), ('sink/u_fifo/fifo/ram_inst/ramread0_syn_6', 'X8Y18Z3'), ('transmitter/u_hdmi_edid_wrapper/u_iic_master_wrapper/u_iic_transmitter_controller/u_iic_w11_d1024_fifo/u_logic_ramfifo_syn_354', 'X24Y63Z0'), ('transmitter/u_hdmi_edid_wrapper/u_iic_master_wrapper/u_iic_transmitter_controller/u_iic_w11_d1024_fifo/u_logic_ramfifo_syn_364', 'X24Y63Z1'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_524', 'X8Y36Z3'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_534', 'X8Y45Z1'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_544', 'X24Y36Z3'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_554', 'X24Y36Z2'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_564', 'X8Y36Z0'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_574', 'X8Y36Z1'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_584', 'X8Y45Z0'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_594', 'X8Y45Z2'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_604', 'X8Y36Z2'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_614', 'X24Y45Z1'), ('transmitter/u_hdmi_tx_controller_wrapper/u_hdmi_island_data_gen/U_audio_sample_packet_2_channel/u_w96_d1024_fifo/u_logic_ramfifo_syn_624', 'X8Y45Z3'), ('transmitter/u_hdmi_tx_controller_wrapper/u_video_axi_stream_receiver/u_w24_d1024_fifo/u_logic_ramfifo_syn_380', 'X24Y54Z3'), ('transmitter/u_hdmi_tx_controller_wrapper/u_video_axi_stream_receiver/u_w24_d1024_fifo/u_logic_ramfifo_syn_390', 'X24Y54Z1'), ('transmitter/u_hdmi_tx_controller_wrapper/u_video_axi_stream_receiver/u_w24_d1024_fifo/u_logic_ramfifo_syn_400', 'X24Y54Z2'), ('uart/g_catalog$parser/ramread0_syn_5', 'X32Y27Z1'), ('uart/replies/ramread0_syn_26', 'X24Y27Z3'), ('uart/replies/ramread0_syn_45', 'X24Y36Z1'), ('uart/replies/ramread0_syn_7', 'X24Y36Z0'), ('video/cache/packed_data$store/ramread0_syn_6', 'X32Y9Z0'), ('video/cache/packed_data$store/ramread1_syn_6', 'X32Y9Z1'), ('video/cache/packed_data$store/ramread2_syn_6', 'X32Y54Z0'), ('video/cache/packed_data$store/ramread3_syn_6', 'X32Y54Z1'), ('video/graphics/ramread0_syn_5', 'X32Y45Z3'), ('video/graphics/ramread2_syn_5', 'X32Y45Z2'), ('video/graphics/spectrum$analyzer/ramread0_syn_5', 'X24Y54Z0'), ('video/graphics/spectrum$analyzer/ramread2_syn_25', 'X24Y45Z0'), ('video/graphics/spectrum$analyzer/ramread2_syn_6', 'X24Y45Z3'))
def assets(root):
 result=[]
 for line in (root/FLOW/'v3_board_assets.list').read_text(encoding='utf-8-sig').splitlines():
  line=line.strip()
  if not line or line.startswith('#'):continue
  rel=Path('safevision')/line
  if not (root/rel).is_file():raise FileNotFoundError('required production ROM asset: '+str(rel))
  if rel in result:raise ValueError('duplicate ROM asset: '+str(rel))
  result.append(rel)
 return result
def sources(root,mode):
 if mode not in ('base','hd'):raise ValueError(mode)
 from v3_source_profiles import source_list
 text=source_list(root,FLOW,mode).read_text(encoding='utf-8-sig')
 result=[]
 for line in text.splitlines():
  line=line.strip()
  if not line or line.startswith('#'):continue
  line=line.replace('@video_pll@','sv_video_hd_pll.v' if mode=='hd' else 'sv_video_vga_pll.v').replace('@mode_define@',mode+'_mode.v')
  path=Path('safevision')/line
  if not (root/path).is_file():raise FileNotFoundError(path)
  if path in result:raise ValueError('duplicate HDL source: '+str(path))
  result.append(path)
 return result
def native_rom_sidecars(root,write=False):


 canonical=root/'safevision/assets/fonts/v3_four_features_text.mem'
 raw=canonical.read_bytes();result=[]
 for mode in ('video','hd'):
  relative=Path('safevision/rtl')/mode/'v3_four_features_text.mem'
  target=root/relative
  if write:target.write_bytes(raw)
  if not target.is_file()or target.read_bytes()!=raw:raise ValueError('native ROM sidecar missing/stale: '+relative.as_posix())
  result.append(relative)
 canonical=root/'safevision/assets/audio/v3_spectrum_twiddle.mem'
 raw=canonical.read_bytes();relative=Path('safevision/rtl/video/v3_spectrum_twiddle.mem');target=root/relative
 if write:target.write_bytes(raw)
 if not target.is_file()or target.read_bytes()!=raw:raise ValueError('native spectrum ROM sidecar missing/stale')
 result.append(relative)
 return result

def scope(root):
 files=set(sources(root,'base')+sources(root,'hd')+assets(root))
 files.add(Path('safevision/assets/fonts/OFL-NotoSansSC.txt'))
 files.add(Path('safevision/platform/anlogic_eg4s20_hx4s20c/ip/protected_sources.sha256.json'))
 files.update(Path('safevision/tools')/name for name in ('check_verilog.py','verilog_tokens.py'))
 files.add(Path('safevision/tools/check_bmp_header_phase.py'))
 from check_source_tree import SUITES
 files.add(Path('safevision/tools/run_v3_sim_flexible.py'))
 for suite in SUITES:
  manifest=Path('safevision/build/manifests')/(suite+'_sim.json')
  files.add(manifest)
  data=json.loads((root/manifest).read_text('utf-8-sig'))
  files.update(Path(n) for key in ('sources','assets','generator_dependencies') for n in data.get(key,[]))
  files.update(Path(n) for n in data.get('generators',{}).values())
  for top in data['tops']:
   tests=data.get('test_sources',{}).get(top,['safevision/verification/unit/'+top+'.v'])
   files.update(Path(n) for n in ([tests] if isinstance(tests,str) else tests))
 files.update(native_rom_sidecars(root))
 for rel in ('safevision/rtl/include','safevision/assets/fonts',str(FLOW)):
  files.update(p.relative_to(root) for p in (root/rel).rglob('*') if p.is_file() and p.suffix in ('.vh','.mem','.sdc','.tcl','.adc','.json','.list','.v','.al'))
 files.update(Path('safevision/tools')/n for n in ('v3_source_profiles.py','v3_sources.py','v3_final_sta.py','check_board_timing.py','check_v3_board.py','check_v3_rom_netlist.py','check_v3_spi_timing.py','check_v3_io_scope.py','run_v3_board.ps1','run_v3_board.py','configure_v3_pll.py','run_v3_pll.py','gen_v3_cdc.py'))
 files.update(Path('safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll')/n for n in ('sv_v3_memory_pll.ipc','sv_v3_memory_pll.provenance.json'))
 files.update(Path('safevision/platform/anlogic_eg4s20_hx4s20c/ip/hdmi_vendor')/n for n in ('source.sha256.json',))
 files.update(Path('safevision/tools')/n for n in ('v3_resource_policy.py','check_v3_board_reference.py','check_v3_command_catalog.py'))
 files.update(Path('safevision/tools')/n for n in ('v3_functional_release.py','check_source_tree.py'))
 files.add(Path('safevision/tools/check_v3_volume_reciprocal.py'))
 files.add(Path('safevision/tools/check_v3_clock_contract.py'))
 files.add(Path('safevision/tools/check_v3_sample_netlist.py'))
 files.add(Path('safevision/tools/check_v3_native_clock_domains.py'))
 files.add(Path('safevision/tools/v3_checkpoint_flow.py'))
 if '.PACKED_EXTERNAL(1)'in (root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text('utf-8-sig'):
  files.add(Path('safevision/tools/build_ticker_shared32_lossless.py'))
 return sorted(files,key=lambda p:p.as_posix())
def snapshot(root):
 from v3_checkpoint_flow import validate
 validate(root)
 from v3_resource_policy import load
 from check_v3_board_reference import check as check_board_reference
 from check_v3_command_catalog import check as check_catalog
 load(root);check_board_reference(root);check_catalog(root)
 from check_v3_clock_contract import check as check_clocks
 check_clocks(root)
 physical_constraint_files(root)
 for mode in ('base','hd'):build_parameters(root,mode)


 allowed={'create_clock','derive_clocks','create_generated_clock','set_input_delay','set_output_delay','set_multicycle_path','set_false_path','set_max_delay','set_clock_uncertainty','set_clock_latency','set_case_analysis'}
 for name in ('v3_board.sdc','v3_cdc.sdc'):
  for line in (root/FLOW/name).read_text(encoding='utf-8-sig').splitlines():
   line=line.strip()
   if not line or line.startswith('#'):continue
   if line.split()[0] not in allowed or '$' in line:raise ValueError('production SDC must be expanded supported statements: '+name+': '+line)
 vendor=root/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/hdmi_vendor'
 provenance=json.loads((vendor/'source.sha256.json').read_text(encoding='utf-8'))


 entries=provenance if isinstance(provenance,list) else provenance.get('files',[])
 if len(entries)!=3:raise ValueError('incomplete vendor dependency provenance')
 if isinstance(entries,dict):entries=[{'path':k,'sha256':v} for k,v in entries.items()]
 for entry in entries:
  name=entry.get('relative_path',entry.get('path',''))
  p=(vendor/name).resolve()
  if not p.is_relative_to(vendor.resolve()):raise ValueError('vendor manifest escaped dependency directory')
  if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=entry['sha256']:raise ValueError('vendor dependency changed or missing: '+str(p))
 return {p.as_posix():hashlib.sha256((root/p).read_bytes()).hexdigest() for p in scope(root)}
def physical_constraint_files(root,mode=None):

 if mode not in (None,'base','hd'):raise ValueError('unknown physical mode')
 common=root/FLOW/'v3_physical.adc'
 extras=[common]+[root/FLOW/('v3_physical_'+m+'.adc')for m in ('base','hd')]

 for extra in extras:
  if not extra.exists():continue
  statements=[s.strip() for s in extra.read_text(encoding='utf-8-sig').splitlines() if s.strip() and not s.lstrip().startswith('#')]
  approved='set_inst_assignment {memory_ip/u2_ram/u2_wrrd/sdr_t_reg} {location = x19y31z1;}'
  phy=['create_bound {v3_phy_region} -mode fixed -width 12 -height 30 -origin {29 8}', 'add_cells_to_bound -bound v3_phy_region -cells {reset_phy serializer}']
  media=[f'set_inst_assignment {{{n}}} {{LOCATION = {loc};}}'for n,loc in BASE_MEDIA_BRAM_LOCATIONS]
  layouts=([approved],[approved]+phy)
  if extra.name=='v3_physical_base.adc':layouts+=([approved]+media,)
  if extra.name=='v3_physical_base.adc':layouts+=([approved]+[f'set_inst_assignment {{{n}}} {{LOCATION = {loc};}}'for n,loc in BASE_SHARED_BRAM_LOCATIONS],)
  if statements not in layouts:raise ValueError('unreviewed internal physical constraint')
 files=[root/FLOW/'v3_board.adc']
 if mode is None:files.extend(p for p in extras if p.exists())
 else:
  extra=root/FLOW/('v3_physical_'+mode+'.adc')
  if not extra.exists():extra=common
  if extra.exists():files.append(extra)
 return files

def required_media_bram_locations(root,mode):

 physical_constraint_files(root,mode)
 if mode!='base':return {}
 path=root/FLOW/'v3_physical_base.adc'
 if not path.is_file():return {}
 text=path.read_text('utf-8-sig')
 lines=[f'set_inst_assignment {{{n}}} {{LOCATION = {loc};}}'for n,loc in BASE_MEDIA_BRAM_LOCATIONS]
 full=[f'set_inst_assignment {{{n}}} {{LOCATION = {loc};}}'for n,loc in BASE_SHARED_BRAM_LOCATIONS]
 if all(line in text.splitlines()for line in full):return dict(BASE_SHARED_BRAM_LOCATIONS)
 return dict(BASE_MEDIA_BRAM_LOCATIONS)if all(line in text.splitlines()for line in lines)else {}

def build_parameters(root,mode=None):

 if mode not in (None,'base','hd'):raise ValueError('unknown build mode')
 required={('rtl','min_control_set'),('rtl','min_ripple_len'),('rtl','infer_fsm'),('gate','map_mode'),('place','effort'),('place','post_place_opt'),('route','timing'),('route','fix_hold')}
 allowed={
  ('rtl','min_control_set'):{str(n) for n in range(1,9)},
  ('rtl','min_ripple_len'):{'8','16','32','64'},('rtl','infer_fsm'):{'on','off'},
  ('gate','map_mode'):{'auto','area_prior','logic_level_prior','balance_explore'},
  ('gate','pack_effort'):{'low','medium','high'},
  ('gate','bdd_opt'):{'on','off'},('gate','lut4_map'):{'on','off'},
  ('place','ce_weight'):{'on'},('place','cn_opt_effort'):{'high'},
  ('place','critical_hfn_opt'):{'on'},('place','enhanced_beeline_opt'):{'3'},
  ('place','effort'):{'low','medium','high'},
  ('place','opt_timing'):{'medium','off'},
  ('place','seed'):{'0','1','7','13','31'},
  ('place','post_place_opt'):{'auto','medium','high','ultra'},
  ('place','hfn_opt_effort'):{'low','medium','high'},
  ('place','pr_strategy'):{str(n) for n in range(1,18)},
  ('route','effort'):{'normal','routability'},('route','timing'):{'on','greedy','off'},('route','fix_hold'):{'on'},
  ('route','post_route_opt'):{'auto','medium','high','ultra'}}
 values={}
 paths=[root/FLOW/'v3_build_parameters.tcl']
 if mode and (root/FLOW/('v3_build_parameters_'+mode+'.tcl')).exists():paths.append(root/FLOW/('v3_build_parameters_'+mode+'.tcl'))
 for index,path in enumerate(paths):
  seen=set()
  for line in path.read_text(encoding='utf-8-sig').splitlines():
   line=line.strip()
   if not line or line.startswith('#'):continue
   match=re.fullmatch(r'set_param (rtl|gate|place|route) (\w+) (\w+)',line)
   if not match:raise ValueError('unsupported build parameter: '+line)
   stage,key,value=match.groups();pair=(stage,key)
   if pair in seen or pair not in allowed or value not in allowed[pair]:raise ValueError('duplicate/unapproved build parameter: '+line)
   seen.add(pair);values[pair]=value
  if index==0 and not required.issubset(seen):raise ValueError('missing common build parameters')

 return [(stage,key,value) for stage in ('rtl','gate','place','route') for (s,key),value in values.items() if s==stage]

def native_parameters(root,folder,stages=('rtl','gate','place','route')):

 result=[]
 for stage,name,value in build_parameters(root,folder.name if folder.name in ('base','hd') else None):
  if stage not in stages:continue
  report_name='place.seed.params' if (stage,name)==('place','seed') else stage+'.params'
  path=folder/report_name;text=path.read_text(encoding='utf-8',errors='replace')
  if stage=='place'and name in('ce_weight','cn_opt_effort','critical_hfn_opt','enhanced_beeline_opt'):
   path=folder/'place.hidden.params';text=path.read_text(encoding='utf-8');report_name=path.name
   hits=re.findall(r'^place '+re.escape(name)+r' (\w+)$',text,re.M)
  elif stage=='route'and name=='post_route_opt':
   path=folder/'route.hidden.params';text=path.read_text(encoding='utf-8');report_name=path.name
   hits=re.findall(r'^route post_route_opt (auto|medium|high|ultra)$',text,re.M)
  elif stage=='gate'and name in ('bdd_opt','lut4_map'):
   path=folder/'gate.hidden.params';text=path.read_text(encoding='utf-8')
   report_name=path.name;hits=re.findall(r'^gate '+re.escape(name)+r' (on|off)$',text,re.M)
  elif (stage,name)==('place','seed'):

   direct=re.fullmatch(r'place seed ([0-9]+)\r?\n',text)
   hits=[direct[1]] if direct else []
  else:hits=re.findall(r'^\s*'+re.escape(name)+r'\s*\|\s*(\w+)\s*\|',text,re.M)
  if hits!=[value]:raise ValueError('native parameter acknowledgement mismatch: '+stage+'/'+name)
  result.append({'stage':stage,'parameter':name,'actual':hits[0],'report_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'native_report':report_name})
 return result
def gui_project(root,mode):

 native_rom_sidecars(root,write=True)
 project_dir=root/FLOW/mode
 project_dir.mkdir(parents=True,exist_ok=True)
 p=ET.Element('Project',Version='3',Minor='2',Path='.')
 ET.SubElement(p,'Project_Created_Time');ET.SubElement(p,'TD_Version').text='6.2.168116'
 ET.SubElement(p,'Name').text='safevision_v3_'+mode
 hw=ET.SubElement(p,'HardWare');ET.SubElement(hw,'Family').text='EG4';ET.SubElement(hw,'Device').text='EG4S20BG256';ET.SubElement(hw,'Speed')
 fs=ET.SubElement(p,'Source_Files');vs=ET.SubElement(fs,'Verilog')
 import os
 def item(parent,path,order,belong):
  f=ET.SubElement(parent,'File',Path=os.path.relpath(path,project_dir).replace('\\','/'));info=ET.SubElement(f,'FileInfo')
  for name,value in (('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo',belong),('CompileOrder',str(order))):ET.SubElement(info,'Attr',Name=name,Val=value)
 for i,path in enumerate(sources(root,mode),1):item(vs,root/path,i,'design_1')
 ad=ET.SubElement(fs,'ADC_FILE')
 physical=physical_constraint_files(root,mode)
 for i,path in enumerate(physical,1):item(ad,path,i,'constraint_1')
 sd=ET.SubElement(fs,'SDC_FILE')
 for i,name in enumerate(('v3_board.sdc','v3_cdc.sdc'),len(physical)+1):item(sd,root/FLOW/name,i,'constraint_1')
 sets=ET.SubElement(p,'FileSets');ds=ET.SubElement(sets,'FileSet',Name='design_1',Type='DesignFiles')
 config=ET.SubElement(ds,'Config');ET.SubElement(config,'Option',Name='IncludeDir',Val=os.path.relpath(root/'safevision/rtl/include',project_dir).replace('\\','/'))
 ET.SubElement(sets,'FileSet',Name='constraint_1',Type='ConstrainFiles')
 top=ET.SubElement(p,'TOP_MODULE')
 for name,value in (('LABEL',''),('MODULE','safevision_v3_top'),('CREATEINDEX','user')):ET.SubElement(top,name).text=value
 for name in ('Property','Device_Settings','Configurations'):ET.SubElement(p,name)
 runs=ET.SubElement(p,'Runs')
 for name,kind,strategy in (('syn_1','Synthesis','Default_Synthesis_Strategy'),('phy_1','PhysicalDesign','Default_PhysicalDesign_Strategy')):
  attrs=dict(Name=name,Type=kind,ConstraintSet='constraint_1',Description='',Active='true')
  if name=='phy_1':attrs['SynRun']='syn_1'
  r=ET.SubElement(runs,'Run',attrs);strategy_node=ET.SubElement(r,'Strategy',Name=strategy);ET.SubElement(r,'UserParams')
  sections={}
  for stage,param,value in build_parameters(root,mode):
   if (name=='syn_1')!=(stage in ('rtl','gate')):continue
   if stage not in sections:sections[stage]=ET.SubElement(strategy_node,{'rtl':'RtlProperty','gate':'GateProperty','place':'PlaceProperty','route':'RouteProperty'}[stage])
   ET.SubElement(sections[stage],param).text=value
 ET.SubElement(p,'Project_Settings')
 ET.indent(p,space='    ');out=project_dir/('safevision_v3_'+mode+'.al')
 ET.ElementTree(p).write(out,encoding='utf-8',xml_declaration=True)

 out.write_bytes(out.read_bytes().replace(b'\r\n',b'\n'))
 for rel in assets(root):shutil.copyfile(root/rel,project_dir/rel.name)


 return out
def check_gui(root,mode):
 path=root/FLOW/mode/('safevision_v3_'+mode+'.al');tree=ET.parse(path)
 actual=[(path.parent/n.attrib['Path']).resolve() for n in tree.findall('./Source_Files/Verilog/File')]
 expected=[(root/p).resolve() for p in sources(root,mode)]
 if actual!=expected:raise ValueError('GUI/CLI ordered HDL list differs: '+mode)
 if tree.findtext('./TOP_MODULE/MODULE')!='safevision_v3_top':raise ValueError('GUI top mismatch')
 if tree.findtext('./TOP_MODULE/CREATEINDEX')!='user':raise ValueError('GUI must honor explicit top instead of automatic top discovery')
 actual_parameters=[]
 for run,stages in [('syn_1',{'RtlProperty':'rtl','GateProperty':'gate'}),('phy_1',{'PlaceProperty':'place','RouteProperty':'route'})]:
  node=tree.find('./Runs/Run[@Name="'+run+'"]/Strategy')
  if node is None:raise ValueError('missing GUI run strategy')
  for child in node:
   if child.tag not in stages:raise ValueError('unexpected GUI strategy property '+child.tag)
   for param in child:actual_parameters.append((stages[child.tag],param.tag,param.text))
 if actual_parameters!=build_parameters(root,mode):raise ValueError('GUI/CLI build parameters differ')
 compile_orders={}
 for node in tree.findall('./Source_Files/*/File'):
  attrs={n.attrib['Name']:n.attrib['Val'] for n in node.findall('./FileInfo/Attr')}
  group=attrs['BelongTo'];order=int(attrs['CompileOrder']);compile_orders.setdefault(group,[]).append(order)
 if any(len(orders)!=len(set(orders)) for orders in compile_orders.values()):raise ValueError('duplicate GUI compile order within file set')
 for section,paths in (('ADC_FILE',physical_constraint_files(root,mode)),('SDC_FILE',[root/FLOW/n for n in ('v3_board.sdc','v3_cdc.sdc')])):
  actual_constraints=[(path.parent/n.attrib['Path']).resolve() for n in tree.findall('./Source_Files/'+section+'/File')]
  expected_constraints=[p.resolve() for p in paths]
  if actual_constraints!=expected_constraints:raise ValueError('GUI/CLI constraints differ: '+mode+'/'+section)
 for node in tree.findall('./Source_Files/*/File'):
  if Path(node.attrib['Path']).is_absolute():raise ValueError('nonportable absolute GUI path')
  attrs={n.attrib['Name']:n.attrib['Val'] for n in node.findall('./FileInfo/Attr')}
  if attrs.get('UsedInSyn')!='true' or attrs.get('UsedInP&R')!='true' or attrs.get('AutoExcluded')=='true':raise ValueError('GUI production dependency excluded')
 roms=[]
 for rel in assets(root):
  source_hash=hashlib.sha256((root/rel).read_bytes()).hexdigest()
  if hashlib.sha256((path.parent/rel.name).read_bytes()).hexdigest()!=source_hash:raise ValueError('GUI ROM copy differs: '+rel.name)
  roms.append({'path':rel.as_posix(),'sha256':source_hash})
 return {'mode':mode,'sources':len(expected),'top':'safevision_v3_top','gui':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'assets':roms,'build_parameters':build_parameters(root,mode)}
def main():
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--gui',action='store_true');ap.add_argument('--snapshot',type=Path);ap.add_argument('--estimate-video',type=Path)
 a=ap.parse_args();root=a.repo.resolve()
 if a.gui:
  for mode in ('base','hd'):gui_project(root,mode)
  print(json.dumps([check_gui(root,m) for m in ('base','hd')],indent=2))
 if a.snapshot:
  dest=a.snapshot.resolve()
  if dest.exists():raise ValueError('use a new empty snapshot directory')
  before=snapshot(root)
  for rel in before:
   target=dest/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(root/rel,target)
  if snapshot(root)!=before:raise RuntimeError('source changed while copying snapshot')
  changes={}
  if a.estimate_video:
   target=dest/'safevision/rtl/video/v3_video_display_core.v';shutil.copyfile(a.estimate_video,target)
   changes[target.relative_to(dest).as_posix()]={'source':str(a.estimate_video),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
  (dest/'snapshot.manifest.json').write_text(json.dumps({'original_sources':before,'estimate_overrides':changes,'validated':False},indent=2),encoding='utf-8')
  print(dest)
if __name__=='__main__':main()
