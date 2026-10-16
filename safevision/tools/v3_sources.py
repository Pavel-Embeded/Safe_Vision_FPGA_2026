"""Shared explicit V3 source/project resolver; never scans RTL for synthesis."""
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FLOW=Path('safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify')
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
 text=(root/FLOW/'v3_board_sources.list').read_text(encoding='utf-8-sig')
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
def scope(root):
 files=set(sources(root,'base')+sources(root,'hd')+assets(root))
 for rel in ('safevision/rtl/include','safevision/assets/fonts',str(FLOW)):
  files.update(p.relative_to(root) for p in (root/rel).rglob('*') if p.is_file() and p.suffix in ('.vh','.mem','.sdc','.tcl','.adc','.json','.list','.v','.al'))
 files.update(Path('safevision/tools')/n for n in ('v3_sources.py','v3_final_sta.py','check_board_timing.py','check_v3_board.py','check_v3_rom_netlist.py','check_v3_spi_timing.py','check_v3_io_scope.py','run_v3_board.ps1','run_v3_board.py','configure_v3_pll.py','run_v3_pll.py','gen_v3_cdc.py'))
 files.update(Path('safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll')/n for n in ('sv_v3_memory_pll.ipc','sv_v3_memory_pll.provenance.json'))
 files.update(Path('safevision/platform/anlogic_eg4s20_hx4s20c/ip/hdmi_vendor')/n for n in ('source.sha256.json','NOTICE.md'))
 files.update(Path('safevision/tools')/n for n in ('v3_resource_policy.py','check_v3_board_reference.py','check_v3_command_catalog.py'))
 return sorted(files,key=lambda p:p.as_posix())
def snapshot(root):
 from v3_resource_policy import load
 from check_v3_board_reference import check as check_board_reference
 from check_v3_command_catalog import check as check_catalog
 load(root);check_board_reference(root);check_catalog(root)
 # TD read_sdc is deferred and has a restricted parser. User Tcl wrappers can
 # silently discard a collection; normal Tcl object auditing is separate.
 allowed={'create_clock','derive_clocks','create_generated_clock','set_input_delay','set_output_delay','set_multicycle_path','set_false_path','set_max_delay','set_clock_uncertainty','set_clock_latency','set_case_analysis'}
 for name in ('v3_board.sdc','v3_cdc.sdc'):
  for line in (root/FLOW/name).read_text(encoding='utf-8-sig').splitlines():
   line=line.strip()
   if not line or line.startswith('#'):continue
   if line.split()[0] not in allowed or '$' in line:raise ValueError('production SDC must be expanded supported statements: '+name+': '+line)
 vendor=root/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/hdmi_vendor'
 provenance=json.loads((vendor/'source.sha256.json').read_text(encoding='utf-8'))
 # Vendor source must retain its exact copied bytes. Its encrypted behavior is
 # outside XSim coverage; preserving the dependency never substitutes for that.
 entries=provenance if isinstance(provenance,list) else provenance.get('files',[])
 if len(entries)!=3:raise ValueError('incomplete vendor dependency provenance')
 if isinstance(entries,dict):entries=[{'path':k,'sha256':v} for k,v in entries.items()]
 for entry in entries:
  name=entry.get('relative_path',entry.get('path',''))
  p=(vendor/name).resolve()
  if not p.is_relative_to(vendor.resolve()):raise ValueError('vendor manifest escaped dependency directory')
  if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=entry['sha256']:raise ValueError('vendor dependency changed or missing: '+str(p))
 return {p.as_posix():hashlib.sha256((root/p).read_bytes()).hexdigest() for p in scope(root)}
def build_parameters(root):
 text=(root/FLOW/'v3_build_parameters.tcl').read_text(encoding='utf-8-sig')
 rows=[]
 for line in text.splitlines():
  line=line.strip()
  if not line or line.startswith('#'):continue
  match=re.fullmatch(r'set_param (rtl|gate|place|route) (\w+) (\w+)',line)
  if not match:raise ValueError('unsupported shared build parameter: '+line)
  rows.append(match.groups())
 expected={('rtl','min_control_set'),('rtl','min_ripple_len'),('rtl','infer_fsm'),('gate','map_mode'),('place','effort'),('place','post_place_opt'),('route','timing'),('route','fix_hold')}
 if len(rows)!=len(expected) or {(r[0],r[1]) for r in rows}!=expected:raise ValueError('missing/duplicate/unapproved shared build parameters')
 if dict(((s,k),v) for s,k,v in rows).get(('route','timing'))!='on' or dict(((s,k),v) for s,k,v in rows).get(('route','fix_hold'))!='on':raise ValueError('setup/hold optimization must remain enabled')
 return rows

def native_parameters(root,folder,stages=('rtl','gate','place','route')):
 """Bind every shared parameter to the tool's actual registered-value table."""
 result=[]
 for stage,name,value in build_parameters(root):
  if stage not in stages:continue
  path=folder/(stage+'.params');text=path.read_text(encoding='utf-8',errors='replace')
  hits=re.findall(r'^\s*'+re.escape(name)+r'\s*\|\s*(\w+)\s*\|',text,re.M)
  if hits!=[value]:raise ValueError('native parameter acknowledgement mismatch: '+stage+'/'+name)
  result.append({'stage':stage,'parameter':name,'actual':hits[0],'report_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 return result
def gui_project(root,mode):
 """Generate portable .al from the same ordered HDL manifest as CLI."""
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
 ad=ET.SubElement(fs,'ADC_FILE');item(ad,root/FLOW/'v3_board.adc',1,'constraint_1')
 sd=ET.SubElement(fs,'SDC_FILE')
 for i,name in enumerate(('v3_board.sdc','v3_cdc.sdc'),2):item(sd,root/FLOW/name,i,'constraint_1')
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
  for stage,param,value in build_parameters(root):
   if (name=='syn_1')!=(stage in ('rtl','gate')):continue
   if stage not in sections:sections[stage]=ET.SubElement(strategy_node,{'rtl':'RtlProperty','gate':'GateProperty','place':'PlaceProperty','route':'RouteProperty'}[stage])
   ET.SubElement(sections[stage],param).text=value
 ET.SubElement(p,'Project_Settings')
 ET.indent(p,space='    ');out=project_dir/('safevision_v3_'+mode+'.al')
 ET.ElementTree(p).write(out,encoding='utf-8',xml_declaration=True)
 for rel in assets(root):shutil.copyfile(root/rel,project_dir/rel.name)
 # Also place the documented default relative font location used by the GUI
 # when TD switches to a synthesis/physical run folder.
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
 if actual_parameters!=build_parameters(root):raise ValueError('GUI/CLI build parameters differ')
 compile_orders={}
 for node in tree.findall('./Source_Files/*/File'):
  attrs={n.attrib['Name']:n.attrib['Val'] for n in node.findall('./FileInfo/Attr')}
  group=attrs['BelongTo'];order=int(attrs['CompileOrder']);compile_orders.setdefault(group,[]).append(order)
 if any(len(orders)!=len(set(orders)) for orders in compile_orders.values()):raise ValueError('duplicate GUI compile order within file set')
 for section,names in (('ADC_FILE',['v3_board.adc']),('SDC_FILE',['v3_board.sdc','v3_cdc.sdc'])):
  actual_constraints=[(path.parent/n.attrib['Path']).resolve() for n in tree.findall('./Source_Files/'+section+'/File')]
  expected_constraints=[(root/FLOW/n).resolve() for n in names]
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
 return {'mode':mode,'sources':len(expected),'top':'safevision_v3_top','gui':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'assets':roms,'build_parameters':build_parameters(root)}
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
