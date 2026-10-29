
import argparse,hashlib,json,re,sys
from pathlib import Path
from datetime import datetime,timezone
from check_board_timing import assess,read_report
from v3_sources import FLOW
from check_v3_rom_netlist import check_roms
from check_v3_spi_timing import check as spi_edge_witness,check_cs
from check_v3_io_scope import bounded_outputs,dead_ddc_input
def resources(text):
 out={}
 for name in ('lut','reg','bram','bram32k','dsp','pll'):
  found=list(re.finditer(r'^#'+name+r'\s+(\d+)\s+out of\s+(\d+)\s+([0-9.]+)%',text,re.M))
  if len(found)!=1:raise ValueError('missing/ambiguous resource '+name)
  m=found[0]
  used,total=int(m[1]),int(m[2]);out[name]={'used':used,'available':total,'percent':100*used/total}
 out['ram']={'used_9k_tiles':out['bram']['used']+4*out['bram32k']['used'],
  'available_9k_tiles':out['bram']['available'],
  'note':'A RAM32K macro consumes four of the physical RAM9K tiles.'}
 out['ram']['percent']=100*out['ram']['used_9k_tiles']/out['ram']['available_9k_tiles']
 return out
def resource_gate(text,policy=None):
 used=resources(text);targets={'lut':70,'reg':65,'ram':75};caps={'lut':80,'reg':80,'ram':85};errors=[]
 from v3_resource_policy import CAPACITY,validate
 if policy is not None:
  validate(policy);targets=policy['targets_percent'];caps=policy['hard_caps_percent']
 for name,capacity in CAPACITY.items():
  if used[name]['available']!=capacity:errors.append(name+' reported capacity differs from EG4S20BG256')
  if used[name]['used']>capacity:errors.append(name+' exceeds physical capacity')
 for name,cap in caps.items():
  if used[name]['percent']>cap:errors.append(f'{name} {used[name]["percent"]:.3f}% exceeds hard cap {cap}%')
 for name in ('dsp','pll'):
  if used[name]['used']>used[name]['available']:errors.append(name+' exceeds physical capacity')
 if used['pll']['used']!=3:errors.append('V3 requires the system, video and audio PLLs (exactly three)')
 return {'resources':used,'resource_targets_percent':targets,'resource_hard_caps_percent':caps,
  'resource_target_met':{name:used[name]['percent']<=limit for name,limit in targets.items()},'errors':errors,'accepted':not errors}
def no_delay_ports(text,kind):
 marker=re.search(r'^\d+\. checking no '+kind+r' delay \(MEDIUM\)\s*\n-+\nThere are (\d+) '+kind+r' ports[^\n]*\n(.*?)(?=^\d+\. checking|\Z)',text,re.M|re.S)
 if not marker:raise ValueError('missing I/O detail: '+kind)
 ports=[s.strip() for s in marker[2].splitlines() if re.fullmatch(r'\s*\w+(?:\[\d+\])?\s*',s)]
 if len(ports)!=int(marker[1]):raise ValueError('I/O detail count mismatch: '+kind)
 return ports

def constraint_objects(text,audit_source):

 errors=[];objects=[]
 for line in text.splitlines()[1:]:
  name,count=line.rsplit('\t',1);count=int(count);objects.append({'label':name,'matched_objects':count})
  if count<=0:errors.append('empty constraint collection: '+name)
 expected=re.findall(r'^v3_expect_objects \{([^}]+)\}',audit_source,re.M)
 if len(expected)<48 or [x['label'] for x in objects]!=expected:
  errors.append('incomplete/reordered/duplicate constraint collection audit')
 return objects,errors

def exception_timing(text):

 from check_board_timing import PATH_RE,point_name
 errors=[];paths=[]
 if not re.search(r'^Confidence\s*:\s*Routed\s*$',text,re.M):errors.append('exception report is not routed')
 for corner in ('Slow','Fast'):
  if not re.search(r'^'+corner+r'\s*\|\s*yes\s+yes\s*$',text,re.M):errors.append('missing exception '+corner+' max/min')
 for m in PATH_RE.finditer(text):
  path={'begin':point_name(m[2]),'end':point_name(m[3]),'type':m[4].lower(),'slack_ns':float(m[1])};paths.append(path)
  if path['type'] not in ('setup','hold','recovery','removal'):errors.append('unknown native exception check type')
  if path['slack_ns']<0:errors.append('negative native exception '+path['type']+' '+path['begin']+' -> '+path['end']+' '+str(path['slack_ns'])+'ns')
 if not paths or len(paths)!=len(re.findall(r'^Slack\s*:',text,re.M)):errors.append('missing/truncated native exception path details')
 for kind,wns,tns,count in re.findall(r'^(Max|Min)\s*:\s*[SH]WNS\s+([-+.0-9]+)ns,\s*[SH]TNS\s+([-+.0-9]+)ns,\s*(\d+) Viol Endpoints',text,re.M):
  if float(wns)<0 or float(tns)<0 or int(count):errors.append('negative/violating native exception '+kind+' summary')
 return {'accepted':not errors,'errors':errors,'path_count':len(paths),'paths':paths}

def exception_paths(text,sdc_sources,mid_ref=False):

 from collections import Counter
 rows=[];errors=[]
 errors.extend(exception_timing(text)['errors'])
 expected=[m[0] for source in sdc_sources for m in re.finditer(r'^set_(?:max_delay|multicycle_path)\b[^\n]*',source,re.M)]


 spi=spi_edge_witness(text,mid_ref=mid_ref) if any('-to [get_clocks sd_ident] 499' in command for command in expected) else None
 if spi and not spi['accepted']:errors.extend('SPI edge witness: '+error for error in spi['errors'])
 witnessed=set(spi['commands']) if spi and spi['accepted'] else set()
 for m in re.finditer(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_(?:max_delay|multicycle_path).*?)\s*$',text,re.M):
  total,dominated,shadowed,ignored=map(int,m.groups()[:4]);command=m[5]
  rows.append({'total':total,'dominated':dominated,'shadowed':shadowed,'ignored':ignored,'command':command})
  detailed_zero=total==dominated==shadowed==ignored==0 and command in witnessed
  if detailed_zero:rows[-1]['native_zero_counter_with_routed_edge_witness']=True
  if not detailed_zero and (total<=0 or dominated!=total or shadowed or ignored):
   errors.append('unused/ignored/partial exception: '+command)
 normalize=lambda value:' '.join(value.split())
 expected=[normalize(command) for command in expected]
 actual=[normalize(row['command']) for row in rows]
 if len(expected)<26 or Counter(actual)!=Counter(expected):
  missing=list((Counter(expected)-Counter(actual)).elements())
  extra=list((Counter(actual)-Counter(expected)).elements())
  errors.append('incomplete/duplicate actual timing-exception path audit; missing='+repr(missing)+' extra='+repr(extra))
 return rows,errors
def clock_definition_health(health):
 errors=[]
 counts=re.findall(r'^\d+\. checking clock definition\((\d+)\)',health,re.M)
 if counts!=['0']:errors.append('V3 missing/nonzero formal clock-definition health')
 masters=re.findall(r'There (?:are|is) (\d+) generated clocks? that (?:are|is) not connected to (?:their|its) master clocks?\.',health)
 if not masters or any(int(x) for x in masters):errors.append('V3 missing/nonzero generated-master connectivity health')
 return errors

def media_bram_locations(text,expected):
 rows=[];errors=[]
 for line in text.splitlines():
  if not line.strip():continue
  match=re.fullmatch(r'set_inst_assignment \{([^}]+)\} \{LOCATION = (X[0-9]+Y[0-9]+Z[0-9]+);\}',line)
  if not match:errors.append('invalid native BRAM placement row');continue
  rows.append(match.groups())
 actual=dict(rows)
 if len(actual)!=len(rows)or not rows:errors.append('missing or duplicate native BRAM placement rows')
 for name,location in expected.items():
  if actual.get(name)!=location:errors.append('media BRAM location differs: '+name)
 return dict(accepted=not errors,errors=errors,reported_brams=len(rows),required_locations=expected,actual_required_locations={name:actual.get(name)for name in expected})

def check(folder,repo):
 errors=[];files=['route.timing','route.check','route.area','route.exceptions','constraint.objects.tsv','route.derived.sdc','route.db','route.netlist.v','gate.hidden.params','gate.netlist.v','route.clocks','route.hidden.params','final_sta.tcl','final_sta.manifest.json','after_clock_report.check','after_clock_report.timing','after_clock_report.exceptions','inprocess.route.timing','inprocess.route.check','inprocess.route.exceptions']
 files.extend(('checkpoint.synthesis.json','synthesis.console.log','implementation.console.log','gate.db','place.hidden.params'))
 from v3_sources import build_parameters,required_media_bram_locations
 mode=folder.name if folder.name in ('base','hd') else None
 required_bram=required_media_bram_locations(repo,mode)
 if required_bram:files.append('route.bram.adc')
 if any((stage,key)==('place','seed') for stage,key,value in build_parameters(repo,mode)):
  files.extend(('place.all.params','place.seed.params'))
 for name in files:
  if not (folder/name).is_file() or not (folder/name).stat().st_size:errors.append('missing/nonempty report: '+name)
 result={'status':'FAIL','gate_accepted':False,'timing_passed':False,'errors':errors}
 if errors:return result
 from v3_checkpoint_flow import verify_receipt
 try:result['checkpoint_handoff']=verify_receipt(folder)
 except (ValueError,KeyError,OSError)as ex:errors.append(str(ex));return result
 integrity=json.loads((folder/'final_sta.manifest.json').read_text(encoding='utf-8'))
 if not integrity.get('accepted') or integrity.get('caller_route_process_exit_code')!=0 or integrity.get('sta_process_exit_code')!=0:errors.append('missing/failed real route and fresh-STA integrity evidence')
 frozen=integrity.get('database_and_constraint_sha256_after',{})
 required_frozen=[folder/'route.db',repo/FLOW/'v3_board.sdc',repo/FLOW/'v3_cdc.sdc',repo/FLOW/'v3_cdc_audit.tcl']
 for path in required_frozen:
  if frozen.get(str(path.resolve()))!=hashlib.sha256(path.read_bytes()).hexdigest():errors.append('fresh-STA frozen input mismatch: '+str(path))
 timing=read_report(folder/'route.timing');health=read_report(folder/'route.check');area=read_report(folder/'route.area');exc=read_report(folder/'route.exceptions')
 sta=assess(timing,health);errors.extend(sta['errors']);result['sta']=sta

 errors.extend(clock_definition_health(health))
 try:
  from v3_source_profiles import native_acknowledgement
  result['native_ordered_source_profile']=native_acknowledgement(repo,folder,folder.name)
  from check_v3_board_reference import check as check_reference
  result['board_reference']=check_reference(repo,area)
  from check_v3_clock_contract import check as check_clock_contract
  result['configured_clock_contract']=check_clock_contract(repo)
  from check_v3_native_clock_domains import check as check_native_clock_domains
  result['native_packed_clock_ownership']=check_native_clock_domains(folder,repo)
  from v3_sources import native_parameters
  result['native_parameters']=native_parameters(repo,folder)
  files+=['rtl.params','gate.params','place.params','route.params']
  result['mapped_roms']=check_roms(read_report(folder/'gate.netlist.v'),repo)
  from check_v3_sample_netlist import check as check_samples
  result['exact_sample_physical_storage']=check_samples(read_report(folder/'route.netlist.v'))
  from v3_resource_policy import load
  result['resource_policy']=load(repo)
  rg=resource_gate(area,result['resource_policy']);errors.extend(rg.pop('errors'));result.update({k:v for k,v in rg.items() if k!='accepted'})
  if required_bram:
   bram_report=folder/'route.bram.adc'
   if integrity.get('bram_location_report_sha256')!=hashlib.sha256(bram_report.read_bytes()).hexdigest():errors.append('fresh-process BRAM placement report identity differs')
   layout=media_bram_locations(read_report(bram_report),required_bram);errors.extend(layout['errors'])
   if layout['reported_brams']!=result['resources']['bram']['used']+result['resources']['bram32k']['used']:errors.append('native BRAM placement inventory differs from native area')
   result['media_bram_locations']=layout
  result['spi_cs_ordinary_paths']=check_cs(timing)
  if not result['spi_cs_ordinary_paths']['accepted']:errors.extend(result['spi_cs_ordinary_paths']['errors'])
  budget=json.loads((repo/FLOW/'io_budget.json').read_text(encoding='utf-8'))
  result['bounded_asynchronous_outputs']=bounded_outputs(exc,budget['asynchronous_bounded_output_ports'])
  if not result['bounded_asynchronous_outputs']['accepted']:errors.extend(result['bounded_asynchronous_outputs']['errors'])
  result['ddc_absent_input']=dead_ddc_input(read_report(folder/'gate.netlist.v'))
  if not result['ddc_absent_input']['accepted']:errors.extend(result['ddc_absent_input']['errors'])
  dead_inputs=set(budget['vendor_absent_input_ports']) if result['ddc_absent_input']['accepted'] else set()
  dead_data_outputs=set(budget['vendor_open_drain_output_ports']) if result['ddc_absent_input']['accepted'] else set()
  bounded=set(budget['asynchronous_bounded_output_ports']) if result['bounded_asynchronous_outputs']['accepted'] else set()
  missing_in=no_delay_ports(health,'input');missing_out=no_delay_ports(health,'output')
  unexpected_in=set(missing_in)-set(budget['asynchronous_input_ports'])-dead_inputs
  unexpected_out=set(missing_out)-set(budget['forwarded_or_vendor_serial_output_ports'])-bounded-dead_data_outputs
  if unexpected_in:errors.append('unbudgeted input ports: '+','.join(sorted(unexpected_in)))
  if unexpected_out:errors.append('unbudgeted output ports: '+','.join(sorted(unexpected_out)))
  for name in ('partial input delay','partial output delay','abnormal input delay'):
   if sta['health'].get(name)!=0:errors.append('missing or nonzero I/O health: '+name)
  result['io_scope']={'without_input_delay':missing_in,'without_output_delay':missing_out,
   'every_missing_port_explicitly_classified':not unexpected_in and not unexpected_out,
   'assumed_pcb_allowance_measured':False,'external_electrical_verified':False,
   'pending_hardware':budget['pending_hardware']}
  audit_source=(repo/FLOW/'v3_cdc_audit.tcl').read_text(encoding='utf-8-sig')
  objects,object_errors=constraint_objects((folder/'constraint.objects.tsv').read_text(encoding='utf-8-sig'),audit_source)
  errors.extend(object_errors)
  result['constraint_objects']=objects
  sdc_sources=[(repo/FLOW/name).read_text(encoding='utf-8-sig') for name in ('v3_board.sdc','v3_cdc.sdc')]
  result['native_exception_timing']=exception_timing(exc)
  rows,path_errors=exception_paths(exc,sdc_sources,mid_ref=(budget['sd'].get('miso_sample_edge')=='falling_ref'));errors.extend(path_errors)
  result['actual_exception_paths']=rows
 except (ValueError,KeyError,OSError) as ex:errors.append(str(ex))
 result['reports']=[{'path':str((folder/n).resolve()),'sha256':hashlib.sha256((folder/n).read_bytes()).hexdigest()} for n in files]
 result['gate_accepted']=not errors;result['timing_passed']=sta['timing_passed'] and not errors;result['status']='FAIL' if errors else 'PASS'
 result['checked_at_utc']=datetime.now(timezone.utc).isoformat()
 return result
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--folder',type=Path,required=True);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=check(a.folder,a.repo)
 except Exception as ex:r={'status':'FAIL','gate_accepted':False,'timing_passed':False,'errors':[str(ex)]}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
 print('V3 BOARD '+r['status']+': '+str(a.output))
 for line in r['errors'][:12]:print('REJECT: '+line)
 return 0 if r['gate_accepted'] else 1
if __name__=='__main__':sys.exit(main())
