"""Independent current-source replay of all preserved and added HDL checks.

The historical matrix and frozen references are read as originally published.
This extension never replaces their inventories or original routed evidence.
"""
import argparse,hashlib,importlib.util,json,re,sys,subprocess
from pathlib import Path
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
from v3_sources import snapshot,FLOW
ROOT=Path(__file__).resolve().parents[2]
def read(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise ValueError(message)
def bind(root,folder,target=None,mutant_sha=None):
 hashes=read(folder/'sources.sha256.json')
 for name,digest in hashes.items():
  if name.startswith('generated:'):
   p=(folder/name[10:]).resolve();require(p.is_relative_to(folder.resolve()),'runtime path escape')
   require(sha(p)==digest,'runtime bytes changed: '+name)
  elif name==target:require(digest==mutant_sha,'mutant capture differs')
  else:
   p=(root/name).resolve();require(p.is_relative_to(root.resolve()),'source path escape')
   require(sha(p)==digest,'source input differs from current files: '+name)
 return len(hashes)

def positive(root,base,suite,top):
 record=read(base/'results.json')
 require(record.get('complete'),'additional positive suite incomplete: '+suite)
 rows=[r for r in record['results']if r['top']==top]
 require(record['suite']==suite and len(rows)==1 and rows[0]['status']=='PASS'and rows[0].get('source_overrides',[])==[],'additional positive result identity or status differs: '+top)
 native=base/top;bind(root,native);raw=audit_file(native/'sim.log',True)
 require(raw['accepted'],'additional positive raw failure: '+top)
 text=(native/'sim.log').read_text('utf-8',errors='replace')
 counts=re.findall(r'\bPASS '+re.escape(top)+r'\b[^\r\n]*\berrors=0\b[^\r\n]*\bcomparisons=(\d+)',text)
 require(len(counts)==1 and int(counts[0])==rows[0]['data_comparisons'],'additional positive raw comparison count differs: '+top)
 return dict(top=top,data_comparisons=int(counts[0]),raw_sha256=raw['sha256'],compiler=graph(root,native,dict(suite=suite,top=top)))

def semantic_controls(root,base,suite,top,wanted):
 rows=read(base/'summary.json')
 require(rows.get('accepted')and len(rows['cases'])==len(wanted),'additional controls incomplete: '+suite)
 require({c['name']for c in rows['cases']}==set(wanted),'additional control inventory differs: '+suite)
 accepted=[]
 for case in rows['cases']:
  require(case['accepted']and case['process_exit']==1 and case['normal_completion'],'additional detector did not finish normally')
  folder=base/case['name'];path=root/case['target'];require(sha(path)==case['original_sha256'],'additional detector source changed')
  text=path.read_text('utf-8-sig');require(text.count(case['before'])==1,'additional detector patch differs')
  mutant=folder/'mutant.v';require(mutant.read_text('utf-8-sig')==text.replace(case['before'],case['after'])and sha(mutant)==case['mutated_sha256'],'additional detector mutant differs')
  native=folder/'native'/top;bind(root,native,case['target'],case['mutated_sha256']);g=graph(root,native,dict(suite=suite,top=top),case)
  log=(native/'sim.log').read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in log and('PASS '+top in log or '[TB] '+top+' done'in log)and'[FAIL]'in log,'additional detector raw evidence changed')
  require(counts==case['error_counts']and any(counts),'additional detector semantic error count absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log,'additional control crashed or skipped')
  accepted.append(dict(name=case['name'],raw_sha256=sha(native/'sim.log'),compiler=g))
 return accepted

def numeric_shape(root,folder):
 recorded=read(folder/'result.json');tool=root/'safevision/tools/check_shape_space261028.py'
 require(recorded.get('accepted')and recorded['source_sha256']==sha(root/'safevision/rtl/media/v3_bmp_normalizer.v')and recorded['tool_sha256']==sha(tool),'integer-domain proof source identity differs')
 spec=importlib.util.spec_from_file_location('ticker_shape_domain_replay',tool)
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 actual=module.check(root)
 for key in ('accepted','scope','width_range','absolute_height_range','dimension_pairs','height_representations','decision_matrix_sha256','source_sha256','tool_sha256'):
  require(actual[key]==recorded[key],'integer-domain replay differs: '+key)
 require(actual['accepted']and actual['dimension_pairs']==16384**2 and actual['height_representations']==2,'integer-domain coverage incomplete')
 return dict(accepted=True,dimension_pairs=actual['dimension_pairs'],decision_matrix_sha256=actual['decision_matrix_sha256'],evidence_sha256=sha(folder/'result.json'),tool_sha256=sha(tool),scope=actual['scope'])

def numeric_geometry_width(root,folder):
 recorded=read(folder/'result.json');tool=root/'safevision/tools/check_geometry_width261028.py'
 require(recorded.get('accepted')and recorded.get('candidate_bits')==23 and recorded.get('height_representations')==2 and recorded.get('discarded_high_tuple_bits')==7 and recorded.get('full_numerator_bits')==25 and recorded.get('minimum_identity')=='N = min(480*W,640*H)'and recorded['source_sha256']==sha(root/'safevision/rtl/media/v3_bmp_normalizer.v')and recorded['tool_sha256']==sha(tool),'geometry-width proof source identity or profile differs')
 spec=importlib.util.spec_from_file_location('ticker_geometry_width_replay',tool)
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 actual=module.check(root)
 keys=('accepted','scope','dimension_pairs','width_range','height_range','height_representations','candidate_bits','original_scratch_bits','discarded_high_tuple_bits','full_numerator_bits','minimum_identity','maximum_initial_numerator','maximum_quotient','subtraction_invariant','vectors_sha256','source_sha256','tool_sha256')
 for key in keys:require(actual[key]==recorded[key],'geometry-width replay differs: '+key)
 require(actual['accepted']and actual['dimension_pairs']==16384**2 and actual['candidate_bits']==23 and actual['original_scratch_bits']==30 and actual['maximum_initial_numerator']==480*16384 and actual['maximum_initial_numerator']<2**23,'geometry-width domain coverage incomplete')
 return dict(accepted=True,dimension_pairs=actual['dimension_pairs'],candidate_bits=actual['candidate_bits'],maximum_initial_numerator=actual['maximum_initial_numerator'],vectors_sha256=actual['vectors_sha256'],evidence_sha256=sha(folder/'result.json'),tool_sha256=sha(tool),scope=actual['scope'])
def live_geometry(root,base):
 suite='geometry_live_miter261028';top='tb_v3_geometry_live_miter'
 checked=positive(root,base/'geometry_live',suite,top)
 folder=base/'geometry_live_controls';row=read(folder/'summary.json')
 target='safevision/rtl/media/v3_bmp_normalizer.v'
 meta=read(root/'safevision/verification/models/v3_bmp_normalizer_frozen_live261028.freeze.json')
 require(meta['parent_commit']=='df73ee8f20fa06b7a048fb2dc3c2c4eefbb5cc49','geometry reference parent changed')
 require(meta['original_path']==target and meta['reference_path']=='safevision/verification/models/v3_bmp_normalizer_frozen_live261028.sv'and meta['rename_from']=='module v3_bmp_normalizer #('and meta['rename_to']=='module v3_bmp_normalizer_frozen_live261028 #(','geometry reference namespace definition changed')
 parent=subprocess.check_output(['git','-C',str(root),'show',meta['parent_commit']+':'+target])
 before=meta['rename_from'].encode();after=meta['rename_to'].encode()
 require(parent.count(before)==1 and hashlib.sha256(parent).hexdigest()==meta['original_sha256'],'geometry parent blob differs')
 require(parent.replace(before,after)==(root/meta['reference_path']).read_bytes()and sha(root/meta['reference_path'])==meta['reference_sha256'],'geometry model is not the exact renamed parent')
 require(row['accepted']and row['rename_only']and row['current_source_sha256']==sha(root/target)==meta['candidate_sha256']and row['reference_sha256']==meta['reference_sha256']and row['tool_sha256']==sha(root/'safevision/tools/test_geometry_live_miter261028.py'),'public-cycle miter identity differs')
 case=row['control'];require(case['name']=='geometry_live_pixel_bit_changed'and case['mutated_public_signal']=='pixel[0]'and case['process_exit']==1 and case['normal_completion']and case['protocol_and_coverage_counters_equal'],'public pixel control incomplete')
 require(row['positive_sha256']==sha(base/'geometry_live/results.json'),'public-cycle positive receipt differs from the control baseline')
 text=(root/target).read_text('utf-8-sig')
 before="EPUSH:begin pixel<=row_black||col_black?16'd0:read_pixel;";after="EPUSH:begin pixel<=(row_black||col_black?16'd0:read_pixel)^16'h0001;"
 require(text.count(before)==1,'public pixel mutation anchor differs')
 mutant=folder/'public_state_mutant.v'
 require(mutant.read_text('utf-8-sig')==text.replace(before,after)and sha(mutant)==case['mutant_sha256'],'public pixel mutation differs')
 native=folder/'native'/top;bind(root,native,target,case['mutant_sha256'])
 g=graph(root,native,dict(suite=suite,top=top),dict(mutated_sha256=case['mutant_sha256']))
 raw=(native/'sim.log').read_text('utf-8',errors='replace')
 require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in raw and'[FAIL] all62FLEX public bits agree'in raw and not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'public pixel detector raw evidence differs')
 pattern=r'PASS '+top+r' errors=(\d+) comparisons=(\d+) cycles=(\d+) frames=(\d+) invalid_sizes=(\d+) invalid_eofs=(\d+) async_checks=(\d+) stalled_cycles=(\d+)'
 pos=re.search(pattern,(base/'geometry_live'/top/'sim.log').read_text('utf-8'));neg=re.search(pattern,raw)
 require(pos and neg and pos[1]=='0'and pos.groups()[1:]==neg.groups()[1:]and int(pos[2])>30000000 and int(pos[3])>1000000 and list(map(int,pos.groups()[3:7]))==[12,16,5,5]and int(pos[8])>100000,'public-cycle miter coverage or timing differs')
 require([int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]==case['error_counts']and int(neg[1])>=307200,'public pixel errors absent')
 return checked,dict(name=case['name'],raw_sha256=sha(native/'sim.log'),compiler=g,protocol_and_coverage_counters_equal=True)

def source_wait(root,base):
 wanted=[('source_wait_watchdog261028','tb_v3_source_wait_watchdog',900000),('source_wait_legacy261028','tb_v3_source_wait_legacy',20000),('source_wait_writer261028','tb_v3_source_wait_writer',6),('progress_wide_independent261028','tb_v3_progress_wide_independent',50000000)]
 positives=[]
 for suite,top,minimum in wanted:
  folder=base/suite;positives.append(positive(root,folder,suite,top))
  result=read(folder/'results.json');require(len(result['results'])==1 and positives[-1]['data_comparisons']>=minimum,'source-wait coverage incomplete: '+top)
 wide=(base/'progress_wide_independent261028/tb_v3_progress_wide_independent/sim.log').read_text('utf-8')
 coverage=re.search(r'raw_bytes=(\d+) pixels=(\d+) writes=(\d+) reads=(\d+) max_pixel_gap_cycles=(\d+) credits=(\d+) busy_saved=(\d+) stale_checks=(\d+) legacy_rejected=(\d+)',wide)
 require(coverage and list(map(int,coverage.groups()[:4]))==[3342390,307200,153600,153600]and int(coverage[5])>50000000 and int(coverage[6])>1000 and int(coverage[7])==1 and int(coverage[8])>0 and int(coverage[9])==1,'real wide-BMP/readback/old-timeout control coverage differs')
 freeze=read(root/'safevision/verification/models/source_wait_legacy261028.freeze.json')
 require({r['module']for r in freeze['records']}=={'frame_writer','bmp_frame_sink'}and len(freeze['records'])==2,'source-wait frozen reference inventory differs')
 frozen_paths={'frame_writer':('safevision/rtl/memory/frame_writer.v','safevision/verification/models/v3_frame_writer_before_source_wait261028.sv','v3_frame_writer_before_source_wait261028'),'bmp_frame_sink':('safevision/platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v','safevision/verification/models/v3_frame_sink_before_source_wait261028.sv','v3_frame_sink_before_source_wait261028')}
 for row in freeze['records']:
  require(row['source_commit']=='2b734a27f213b8b28e7daf832a2c7d2a413b30e3','source-wait reference commit differs')
  source_path,reference_path,reference_module=frozen_paths[row['module']]
  require((row['source_path'],row['reference_path'],row['reference_module'])==(source_path,reference_path,reference_module)and row['namespace_only']==['module '+row['module']+' #(','module '+reference_module+' #('],'source-wait reference namespace definition changed')
  original=subprocess.check_output(['git','-C',str(root),'show',row['source_commit']+':'+row['source_path']])
  before,after=(v.encode()for v in row['namespace_only'])
  require(original.count(before)==1 and hashlib.sha256(original).hexdigest()==row['original_sha256']and original.replace(before,after)==(root/row['reference_path']).read_bytes()and sha(root/row['reference_path'])==row['reference_sha256'],'source-wait frozen model differs beyond module name')
 folder=base/'source_wait_controls';summary=read(folder/'summary.json')
 require(summary['driver_sha256']==sha(root/'safevision/tools/test_source_wait_watchdog261028.py')and summary['runner_sha256']==sha(root/'safevision/tools/run_v3_sim_flexible.py'),'source-wait control driver or runner differs')
 writer='safevision/rtl/memory/frame_writer.v';sink='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v'
 inventory={
  'pending_write_hint_unprotected':(writer,'SOURCE_PROGRESS_AWARE && source_progress && !wr_pending && !din_valid','SOURCE_PROGRESS_AWARE && source_progress && !din_valid','source_wait_writer261028','tb_v3_source_wait_writer'),
  'legacy_hint_enabled':(writer,'SOURCE_PROGRESS_AWARE && source_progress && !wr_pending && !din_valid',"1'b1 && source_progress && !wr_pending && !din_valid",'source_wait_legacy261028','tb_v3_source_wait_legacy'),
  'deadline_priority_lost':(sink,'SOURCE_PROGRESS_AWARE && (source_wait_credit || br_px_cnt!=px_d)',"1'b0 && (source_wait_credit || br_px_cnt!=px_d)",'source_wait_watchdog261028','tb_v3_source_wait_watchdog'),
  'physical_drain_guard_lost':(sink,'state_o==S_WRITE && fa_sync[2] && write_drained &&','state_o==S_WRITE && fa_sync[2] &&','source_wait_watchdog261028','tb_v3_source_wait_watchdog')}
 require(summary['accepted']and len(summary['cases'])==4 and {r['name']for r in summary['cases']}==set(inventory),'source-wait control inventory differs')
 controls=[]
 for row in summary['cases']:
  require(tuple(row[k]for k in('target','before','after','suite','top'))==inventory[row['name']],'source-wait control definition changed')
  require(row['accepted']and row['process_exit']==1 and row['normal_completion'],'source-wait control failed to finish normally')
  source=root/row['target'];text=source.read_text('utf-8-sig');require(sha(source)==row['original_sha256']and text.count(row['before'])==1,'source-wait source/anchor differs')
  trial=folder/row['name'];mutant=trial/'mutant.v';native=trial/'native'/row['top']
  require(mutant.read_text('utf-8-sig')==text.replace(row['before'],row['after'])and sha(mutant)==row['mutated_sha256'],'source-wait control bytes differ')
  bind(root,native,row['target'],row['mutated_sha256']);g=graph(root,native,dict(suite=row['suite'],top=row['top']),row)
  raw=(native/'sim.log').read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]
  require(sha(native/'sim.log')==row['sim_sha256']and'$finish called'in raw and'PASS '+row['top']in raw and'[FAIL]'in raw and counts==row['error_counts']and any(counts),'source-wait semantic detection absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'source-wait detector crashed or skipped')
  controls.append(dict(name=row['name'],raw_sha256=sha(native/'sim.log'),compiler=g))
 return positives,controls,dict(raw_bytes=3342390,pixels=307200,write_words=153600,readback_words=153600,maximum_no_pixel_cycles=int(coverage[5]),source_event_retained_after_healthy_read=True,old_pixel_watchdog_rejected=True)

def packed_font(root,base):
 meta=read(root/'safevision/verification/models/v3_scrolling_ticker_frozen_packed32.freeze.json')
 require(meta['parent_commit']=='c528fe3bab995d7f1acf151c72e43e6482e2e4b8'and meta['source_path']=='safevision/rtl/video/v3_scrolling_ticker.v'and meta['reference_path']=='safevision/verification/models/v3_scrolling_ticker_frozen_packed32.sv','lossless font reference identity differs')
 require(meta['rename_from']=='module v3_scrolling_ticker #('and meta['rename_to']=='module v3_scrolling_ticker_frozen_packed32 #(','lossless font reference rename differs')
 parent=subprocess.check_output(['git','-C',str(root),'cat-file','blob',meta['parent_commit']+':'+meta['source_path']])
 require(hashlib.sha256(parent).hexdigest()==meta['source_sha256']and parent.count(meta['rename_from'].encode())==1,'lossless font parent blob differs')
 reference=root/meta['reference_path'];require(reference.read_bytes()==parent.replace(meta['rename_from'].encode(),meta['rename_to'].encode())and sha(reference)==meta['reference_sha256'],'lossless font reference changed beyond its module declaration')
 from build_ticker_shared32_lossless import build
 generated,proof=build(root)
 require(proof['message_characters']==32 and proof['font_payload_words']==626 and proof['font_word_bits']==8 and proof['decoded_bit_comparisons']==8192 and proof['all_pixels_preserved']and proof['coefficient_and_display_prefix_preserved'],'lossless32 generator coverage differs')
 require(all((root/name).read_bytes()==raw for name,raw in generated.items()),'packed font artifacts are stale')
 additions=[positive(root,base/suite,suite,top)for suite,top in [('lossless_shared32','tb_v3_lossless_shared32'),('lossless_shared32_fft','tb_v3_lossless_shared32_fft')]]
 miter=(base/'lossless_shared32/tb_v3_lossless_shared32/sim.log').read_text('utf-8')
 fft=(base/'lossless_shared32_fft/tb_v3_lossless_shared32_fft/sim.log').read_text('utf-8')
 for name in ('high_reads','highest_bit_reads'):require(int(re.search(r'\b'+name+r'=(\d+)',miter)[1])>1000,'lossless font address/data bit coverage absent')
 for name,minimum in [('font_reads',100000),('high_reads',1000),('highest_reads',1000),('contested',0),('spectra',5),('display_reads',100000)]:require(int(re.search(r'\b'+name+r'=(\d+)',fft)[1])>minimum,'packed FFT contention or display coverage absent: '+name)
 from test_lossless_shared32_controls import CASES
 wanted={c[0]for c in CASES};require(wanted=={'font_high_address_lost','font_highest_bit_lost','font_quotient_corrupt','font_latency_extra_clock','font_publication_not_held'},'packed font control inventory differs')
 folder=base/'lossless_shared32_controls';summary=read(folder/'summary.json');require(summary['accepted']and len(summary['cases'])==5,'packed font controls incomplete')
 checked=[]
 for name,target,before,after,suite,top in CASES:
  rows=[r for r in summary['cases']if r['name']==name];require(len(rows)==1,'packed font control duplicated or missing')
  row=rows[0];require(tuple(row[k]for k in('target','before','after','suite','top'))==(target,before,after,suite,top),'packed font control definition differs')
  # Reuse the same complete native receipt checks as all other semantic controls.
  trial=folder/name;one=read(trial/'result.json');require(row==one,'packed font control summary differs from its native result')
  require(row['accepted']and row['process_exit']==1 and row['normal_completion'],'packed font control did not detect normally')
  text=(root/target).read_text('utf-8-sig');require(sha(root/target)==row['original_sha256']and text.count(before)==1,'packed font control input differs')
  require((trial/'mutant.v').read_text('utf-8-sig')==text.replace(before,after)and sha(trial/'mutant.v')==row['mutated_sha256'],'packed font mutant differs')
  native=trial/'native'/top;bind(root,native,target,row['mutated_sha256']);g=graph(root,native,dict(suite=suite,top=top),row)
  raw=(native/'sim.log').read_text('utf-8');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]
  require(sha(native/'sim.log')==row['sim_sha256']and'$finish called'in raw and'PASS '+top in raw and'[FAIL]'in raw and counts==row['error_counts']and any(counts),'packed font control raw detection absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'packed font detector crashed or skipped')
  checked.append(dict(name=name,raw_sha256=sha(native/'sim.log'),compiler=g))
 return additions,checked,proof

def pointer_compare(root,base):
 from check_ring_pointer_compare import check
 recorded=read(base/'pointer_numeric/result.json');actual=check(root)
 require(actual==recorded and actual['accepted']and actual['request_latency_unchanged']and actual['original_arithmetic_status_unchanged'],'pointer mathematical proof or exact source transformation differs')
 additions=[positive(root,base/name,suite,top)for name,suite,top in [('pointer_miter','ring_pointer_compare','tb_v3_ring_pointer_compare'),('pointer_audio','audio_system_pointer','tb_v3_audio_system_pointer')]]
 detector=positive(root,base/'pointer_detector','ring_pointer_trace','tb_v3_ring_pointer_trace')
 raw=(base/'pointer_detector/tb_v3_ring_pointer_trace/sim.log').read_text('utf-8');require(re.findall(r'\bdata_errors=(\d+)',raw)==['0'],'original bounded detector has comparison errors')
 from test_ring_pointer_controls import CASES
 require({c[0]for c in CASES}=={'ring_empty_inverted','ring_full_wrong_phase','ring_empty_ignores_wrap','ring_status_bit_changed','ring_production_mode_disabled','ring_occupancy_sign_reversed','ring_occupancy_owner_leaks','ring_occupancy_read_ignored'},'pointer detector inventory differs')
 folder=base/'pointer_controls';summary=read(folder/'summary.json');require(actual['registered_occupancy']and summary['accepted']and len(summary['cases'])==8,'pointer/occupancy semantic controls incomplete')
 verified=[]
 for name,target,before,after,suite,top in CASES:
  rows=[r for r in summary['cases']if r['name']==name];require(len(rows)==1,'pointer control duplicated or absent');row=rows[0]
  require(tuple(row[k]for k in('target','before','after','suite','top'))==(target,before,after,suite,top),'pointer control definition differs')
  trial=folder/name;require(read(trial/'result.json')==row and row['accepted']and row['process_exit']==1 and row['normal_completion'],'pointer control did not finish normally')
  text=(root/target).read_text('utf-8-sig');require(sha(root/target)==row['original_sha256']and text.count(before)==1,'pointer control source differs')
  require((trial/'mutant.v').read_text('utf-8-sig')==text.replace(before,after)and sha(trial/'mutant.v')==row['mutated_sha256'],'pointer mutation differs')
  native=trial/'native'/top;bind(root,native,target,row['mutated_sha256']);g=graph(root,native,dict(suite=suite,top=top),row)
  raw=(native/'sim.log').read_text('utf-8');counts=[int(v)for v in re.findall(r'errors\s*=\s*(\d+)',raw)]
  require(sha(native/'sim.log')==row['sim_sha256']and'$finish called'in raw and'PASS '+top in raw and'[FAIL]'in raw and counts==row['error_counts']and any(counts),'pointer raw semantic detection absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'pointer control crashed or skipped')
  if suite=='ring_pointer_trace':
   values=re.findall(r'\bdata_errors=(\d+)',raw);require(len(values)==1 and int(values[0])==row['actual_data_comparison_errors']and int(values[0])>0,'pointer control detected only a driver stall')
   require(re.search(r'\[FAIL\].*(?:every public output|occupancies|prefetch threshold|independent PCM)',raw),'pointer comparison detector absent')
  else:require('[FAIL] production selects direct full/empty pointer scheduling'in raw,'production pointer selection detector absent')
  verified.append(dict(name=name,raw_sha256=sha(native/'sim.log'),compiler=g))
 return additions,dict(mathematical_proof=actual,detector_baseline=detector,semantic_controls=verified)

def bmp_extent(root,base):
 from check_bmp_header_phase import check
 recorded=read(base/'bmp_extent_numeric/result.json');actual=check(root)
 require(actual==recorded and actual['accepted']and actual['legacy_flex0_combinational_behavior_preserved']and actual['all_other_parser_state_and_outputs_unchanged'],'BMP source transform or arithmetic proof differs')
 require(actual['extent_sum_bits']==33 and actual['private_sum_stages']==0 and actual['late_capture_bytes']==[52,53] and actual['setup_cycles']==2 and actual['hold_cycles']==1 and actual['minimum_stable_cycles']==19 and actual['header_publication_byte']==53 and actual['conservative_latest_settle_byte']<53,'BMP pipeline contract differs')
 require(actual['bound_transitivity_proven']and actual['bound_weak_order_classes']==13,'BMP comparison transitivity proof absent')
 suite='bmp_extent_pipeline';top='tb_v3_bmp_extent_pipeline'
 extra=positive(root,base/'bmp_extent',suite,top)
 raw=(base/'bmp_extent'/top/'sim.log').read_text('utf-8')
 require(re.findall(r'\bdata_errors=(\d+)',raw)==['0']and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']and'cases=2048'in raw,'BMP public comparison baseline incomplete')
 require(re.findall(r'\bphase_errors=(\d+)',raw)[-1:]==['0'] and sum(map(int,re.findall(r'late_checks=(\d+)',raw)))>=15984,'late-header stable-data assertions incomplete')
 from test_bmp_header_phase_controls import CASES,SOURCE
 require({c[0]for c in CASES}=={'extent_carry_lost','extent_equal_rejected','dib_high_borrow_lost'}and SOURCE=='safevision/rtl/media/bmp_parser.v','BMP semantic inventory differs')
 folder=base/'bmp_extent_controls';summary=read(folder/'summary.json');require(summary['accepted']and len(summary['cases'])==3,'BMP controls incomplete')
 verified=[]
 for name,before,after in CASES:
  rows=[r for r in summary['cases']if r['name']==name];require(len(rows)==1,'BMP control duplicated or absent');row=rows[0]
  require(tuple(row[k]for k in('target','before','after','suite','top'))==(SOURCE,before,after,suite,top),'BMP mutation definition differs')
  trial=folder/name;require(read(trial/'result.json')==row and row['accepted']and row['process_exit']==1 and row['normal_completion'],'BMP control did not finish normally')
  text=(root/SOURCE).read_text('utf-8-sig');require(sha(root/SOURCE)==row['original_sha256']and text.count(before)==1,'BMP control source differs')
  require((trial/'mutant.v').read_text('utf-8-sig')==text.replace(before,after)and sha(trial/'mutant.v')==row['mutated_sha256'],'BMP mutant differs')
  native=trial/'native'/top;bind(root,native,SOURCE,row['mutated_sha256']);g=graph(root,native,dict(suite=suite,top=top),row)
  raw=(native/'sim.log').read_text('utf-8');counts=[int(v)for v in re.findall(r'errors\s*=\s*(\d+)',raw)]
  require(sha(native/'sim.log')==row['sim_sha256']and'$finish called'in raw and'PASS '+top in raw and'[FAIL] every public parser output'in raw and counts==row['error_counts']and any(counts),'BMP raw semantic detection absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'BMP control crashed or skipped')
  values=re.findall(r'\bdata_errors=(\d+)',raw)
  require(len(values)==1 and int(values[0])==row['actual_data_comparison_errors']and int(values[0])>0 and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']and row['driver_errors']==0,'BMP control found only a driver fault')
  verified.append(dict(name=name,raw_sha256=sha(native/'sim.log'),compiler=g))
 # This control tests the timing contract, not public functional behavior.
 trial=base/'bmp_phase_contract';row=read(trial/'result.json')
 before="((hcnt==6'd52)||(hcnt==6'd53))";after="(hcnt>=6'd28)"
 require(row['accepted'] and row['classification']=='Timing stability contract detection, not a public-functional failure' and row['before']==before and row['after']==after and row['target']==SOURCE,'phase control identity differs')
 text=(root/SOURCE).read_text('utf-8-sig');require(text.count(before)==1 and sha(root/SOURCE)==row['original_sha256'],'phase control source differs')
 mutant=trial/'mutant.v';require(mutant.read_text('utf-8-sig')==text.replace(before,after) and sha(mutant)==row['mutated_sha256'],'phase mutant differs')
 native=trial/'native'/top;bind(root,native,SOURCE,row['mutated_sha256']);g=graph(root,native,dict(suite=suite,top=top),row)
 raw=(native/'sim.log').read_text('utf-8');values=re.findall(r'PASS tb_v3_bmp_extent_pipeline errors=(\d+) comparisons=(\d+) data_errors=(\d+) driver_errors=(\d+) phase_errors=(\d+) cases=2048',raw)
 require(len(values)==1 and row['process_exit']==1 and row['normal_completion'] and '$finish called'in raw and sha(native/'sim.log')==row['sim_sha256'],'phase detector did not finish normally')
 errors,comparisons,data_errors,driver_errors,phase_errors=map(int,values[0])
 require(errors>0 and comparisons>=1000000 and data_errors==0 and driver_errors==0 and phase_errors==row['timing_contract_errors'] and phase_errors>0,'phase stability detector failed')
 require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'phase detector crashed or skipped')
 return [extra],verified,dict(mathematical_proof=actual,semantic_controls=verified,timing_contract_control=dict(name=row['name'],errors=phase_errors,raw_sha256=sha(native/'sim.log'),compiler=g),timing_contract_control_counted_as_semantic=False)


def fs_timeout_pipeline(root,base):
 from check_fs_timeout_pipeline import check
 actual=check(root);recorded=read(base/'fs_timeout_numeric/result.json')
 require(actual==recorded and actual['accepted']and actual['normal_protocol']['eligible_states']>0 and not actual['no_bubble_contract_control']['accepted'],'file timeout protocol/source proof differs')
 require(actual['public_data_and_latency_unchanged']and actual['timeout_threshold_unchanged']and not actual['new_timing_exception'],'file timeout contract changed')
 suite='fs_timeout_pipeline';top='tb_v3_fs_timeout_pipeline'
 item=positive(root,base/'fs_timeout_miter',suite,top);raw=(base/'fs_timeout_miter'/top/'sim.log').read_text('utf-8')
 require(item['data_comparisons']>=8000000 and re.findall(r'\bdata_errors=(\d+)',raw)==['0']and re.findall(r'\bphase_errors=(\d+)',raw)==['0']and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']and'cases=256'in raw,'complete file-kernel comparison absent')
 ports='context_out idle_between_sectors busy done error err_code err_detail bytes_rd dbg_state data valid sof eof wk_cur_clus wk_start wk_rst_walk sd_rd_addr sd_rd_len sd_rd_en sd_data_ready lba_cluster timeout_tick timeout_reset lba_request'.split()
 tb=(root/'safevision/verification/unit/tb_v3_fs_timeout_pipeline.sv').read_text('utf-8-sig')
 for prefix in('d','g'):
  vector='wire[321:0] '+prefix+'_public={'+','.join(prefix+'_'+name for name in ports)+'};'
  require(vector in tb,'all322public bits must be compared, including timeout_reset')
  for name in ports:require(tb.count('.'+name+'('+prefix+'_'+name+')')==1,'public output omitted from reference/DUT: '+name)
 require('differs at consumption edge'in tb,'consumption-edge comparison absent')
 from test_fs_timeout_controls import CASES,SOURCE
 wanted={'predicate_stuck_zero','predicate_stuck_one'}
 require({c[0]for c in CASES}==wanted and SOURCE=='safevision/rtl/storage/v3_file_streamer_compact_ctx.v','file timeout mutant inventory differs')
 folder=base/'fs_timeout_controls';summary=read(folder/'summary.json')
 for name,before,after in CASES:
  rows=[r for r in summary['cases']if r['name']==name];require(len(rows)==1,'file timeout control missing/duplicate');row=rows[0]
  require((row['target'],row['before'],row['after'])==(SOURCE,before,after),'file timeout control definition differs')
 checked=semantic_controls(root,folder,suite,top,wanted)
 for row in summary['cases']:
  log=(folder/row['name']/'native'/top/'sim.log').read_text('utf-8');values=re.findall(r'\bdata_errors=(\d+)',log)
  require(len(values)==1 and int(values[0])==row['actual_data_comparison_errors']and int(values[0])>0 and re.findall(r'\bdriver_errors=(\d+)',log)==['0']and'[FAIL] full file-streamer public interface differs'in log,'control detected only an internal phase assertion')
 return [item],checked,dict(protocol_proof=actual,semantic_controls=checked,complete_public_bits=322,consumption_and_updated_edges_compared=True)

def direct_row_lookup(root,base):
 from check_direct_row_lookup import check
 actual=check(root);recorded=read(base/'direct_row_numeric/result.json')
 require(actual==recorded and actual['accepted']and actual['cases']==4096 and actual['unique_valid_signature_rows']==1920,'direct-row complete source/address-domain proof differs')
 require(actual['valid_queries']==3360 and actual['invalid_queries']==736 and actual['added_latency_cycles']==0 and not actual['CRC_operators_or_state_updates_changed']and not actual['new_clock_domain']and not actual['new_timing_exception'],'direct-row contract/CRC/timing scope differs')
 from test_direct_row_controls import CASES
 require({c[0]for c in CASES}=={'slot_carry_lost','row_index_shifted'},'direct-row mutant inventory differs')
 ports='verify_done verify_pass fault approved rd_req rd_addr rd_len lookup_crc lookup_valid bad_addr bad_expected bad_actual source_words checked_rows'.split()
 positives=[];controls=[]
 for mode in('base','hd'):
  suite='direct_row_'+mode+'113';top='tb_v3_direct_row_'+mode;folder=base/('direct_row_'+mode)
  item=positive(root,folder,suite,top);raw=(folder/top/'sim.log').read_text('utf-8')
  require(item['data_comparisons']>=2800000 and re.findall(r'\bdata_errors=(\d+)',raw)==['0']and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']and re.findall(r'\bgold_errors=(\d+)',raw)==['0']and re.findall(r'\bqueries=(\d+)',raw)==['4096']and re.findall(r'\bverified_frames=(\d+)',raw)==['4']and'public_bits=233'in raw,'direct-row complete public/independent CRC coverage absent')
  tb=(root/('safevision/verification/unit/'+top+'.sv')).read_text('utf-8-sig')
  for prefix in('d','g'):
   require('wire[232:0] '+prefix+'_public={'+','.join(prefix+'_'+name for name in ports)+'};'in tb,'row-guard output omitted from public comparison')
   for name in ports:require(tb.count('.'+name+'('+prefix+'_'+name+')')==1,'row-guard output missing/duplicated')
  require('if(rst_n)compare_public;'in tb and'#1;if(rst_n)compare_public;'in tb,'row-guard consumption/update edge comparison absent')
  positives.append(item);folder=base/'direct_row_controls'/mode
  summary=read(folder/'summary.json');target='safevision/rtl/'+('memory'if mode=='base'else'hd')+'/v3_row_integrity.v'
  for name,start,end in CASES:
   rows=[r for r in summary['cases']if r['name']==name];require(len(rows)==1,'direct-row control missing/duplicate')
   require(tuple(rows[0][k]for k in('target','before','after','suite','top'))==(target,start,end,suite,top),'direct-row mutation definition differs')
  checked=semantic_controls(root,folder,suite,top,{c[0]for c in CASES})
  for row in summary['cases']:
   raw=(folder/row['name']/'native'/top/'sim.log').read_text('utf-8');values=re.findall(r'\bdata_errors=(\d+)',raw)
   require(len(values)==1 and int(values[0])==row['actual_data_comparison_errors']and int(values[0])>0 and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']and re.findall(r'\bqueries=(\d+)',raw)==['4096']and re.findall(r'\bverified_frames=(\d+)',raw)==['4'],'direct-row mutation detected only a driver failure')
  controls += [dict(profile=mode,**row)for row in checked]
 return positives,controls,dict(source_and_domain=actual,public_output_bits=233,independent_CRC_model='Python zlib CRC32 of little-endian source words',profiles=['base','hd'],semantic_controls=controls)

def decimal_dsp(root,base):
 from check_decimal_dsp import check
 actual=check(root);recorded=read(base/'decimal_numeric/result.json')
 require(actual==recorded and actual['accepted']and actual['domain_pairs']==268435456 and actual['public_state_reset_and_latency_unchanged']and actual['added_latency_cycles']==0 and not actual['new_timing_exception'],'decimal whole-source/integer proof differs')
 exhaustive=read(base/'decimal_exhaustive/result.json')
 require(exhaustive['accepted']and exhaustive['binding']==actual and exhaustive['comparisons']==268435456 and exhaustive['mismatches']==0 and exhaustive['times9_disagreements']==268435440 and exhaustive['missing_nibble_disagreements']==251658240,'decimal exhaustive domain/control receipt differs')
 require(exhaustive['tool_sha256']==sha(root/'safevision/tools/check_decimal_dsp_exhaustive.py'),'decimal exhaustive helper changed')
 suite='decimal_dsp_miter';top='tb_v3_decimal_dsp_miter'
 item=positive(root,base/'decimal_miter',suite,top);raw=(base/'decimal_miter'/top/'sim.log').read_text('utf-8')
 require(item['data_comparisons']>=900000 and re.findall(r'\bdata_errors=(\d+)',raw)==['0']and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']and'DECIMAL public_bits=186'in raw,'complete decimal public miter absent')
 tb=(root/'safevision/verification/unit/tb_v3_decimal_dsp_miter.sv').read_text('utf-8-sig')
 require('wire[185:0] d_public={cv,target,name,value,q,pv,code,rejected,catalog_id};'in tb and'wire[185:0] g_public={ocv,otarget,oname,ovalue,oq,opv,ocode,orejected,oid};'in tb,'decimal output omitted from complete tuple')
 require('always @(posedge clk)begin #2;compare_public();end'in tb and'always @(negedge clk)begin #2;compare_public();end'in tb,'decimal half-edge comparison absent')
 from test_decimal_dsp_controls import CASES,SOURCE
 require({c[0]for c in CASES}=={'times9','missing_nibble'}and SOURCE=='safevision/rtl/control/v3_command_parser_catalog.v','decimal control inventory differs')
 folder=base/'decimal_controls';summary=read(folder/'summary.json')
 for name,before,after in CASES:
  rows=[r for r in summary['cases']if r['name']==name];require(len(rows)==1,'decimal control missing/duplicated')
  require(tuple(rows[0][k]for k in('target','before','after','suite','top'))==(SOURCE,before,after,suite,top),'decimal control definition differs')
 checked=semantic_controls(root,folder,suite,top,{c[0]for c in CASES})
 for row in summary['cases']:
  log=(folder/row['name']/'native'/top/'sim.log').read_text('utf-8');counts=re.findall(r'\bdata_errors=(\d+)',log)
  require(len(counts)==1 and int(counts[0])==row['actual_data_comparison_errors']and int(counts[0])>0 and re.findall(r'\bdriver_errors=(\d+)',log)==['0']and'[FAIL] full decimal parser public interface differs'in log,'decimal control detected only a driver failure')
 return [item],checked,dict(source_and_identity=actual,exhaustive_domain=exhaustive,complete_public_bits=186,semantic_controls=checked)

def audit(root,regression,ticker,board,controls):
 require(__debug__,'assertions disabled')
 matrix=read(root/'safevision/build/qualification/four_features_261020.json')
 original=json.loads(subprocess.check_output(['git','-C',str(root),'cat-file','blob','09faac2e8fa718c9f92ef4a5013b68003ec8afe6:safevision/build/qualification/four_features_261020.json']))
 require(matrix==original,'historical matrix or frozen references were rebased')
 require(len(matrix['positive'])==303 and len(matrix['negative'])==221,'preserved inventory changed')
 sources=snapshot(root);old=matrix['physical_source_sha256']
 allowed={str(FLOW/n).replace('\\','/')for n in ('base/safevision_v3_base.al','hd/safevision_v3_hd.al','v3_board_assets.list','v3_board_sources.list','v3_board_sources_hd.list','v3_build_parameters_base.tcl')}
 allowed|={'safevision/tools/check_v3_rom_netlist.py','safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v','safevision/rtl/storage/sd_bmp_player.v'}
 allowed|={'safevision/rtl/video/v3_audio_spectrum.v','safevision/rtl/video/v3_status_layers.v','safevision/rtl/video/v3_video_display_core.v'}
 allowed|={'safevision/rtl/media/v3_bmp_normalizer.v','safevision/rtl/hd/v3_status_layers.v','safevision/rtl/hd/v3_video_display_core.v'}
 allowed|={'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v','safevision/rtl/top/safevision_core/bmp_frame_write_bridge.v','safevision/rtl/memory/frame_writer.v'}
 layout_files={'safevision/tools/v3_sources.py','safevision/tools/v3_final_sta.py','safevision/tools/check_v3_board.py',str(FLOW/'v3_physical_base.adc').replace('\\','/')}
 allowed|=layout_files
 top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text('utf-8-sig')
 decimal_reallocation="decimal_product=number*4'd10;"in(root/'safevision/rtl/control/v3_command_parser_catalog.v').read_text('utf-8-sig')
 if decimal_reallocation:allowed.add('safevision/rtl/control/v3_command_parser_catalog.v')
 request_boundary='(* keep="true" *) wire[3:0] requests=found&~fallback&slot_fill&sector_room;'in(root/'safevision/rtl/storage/v3_wav_source.v').read_text('utf-8-sig')
 if request_boundary:allowed.add('safevision/rtl/storage/v3_wav_source.v')
 direct_lookup=top.count('.DIRECT_LOOKUP(1)')==1
 if direct_lookup:allowed|={'safevision/rtl/video/v3_line_cache.v','safevision/rtl/memory/v3_row_integrity.v','safevision/rtl/hd/v3_line_cache.v','safevision/rtl/hd/v3_row_integrity.v'}
 direct_pointer=top.count('.DIRECT_RING_COMPARE(TICKER_ENABLE)')==1
 if direct_pointer:allowed|={'safevision/rtl/audio/v3_pcm_ring.v','safevision/rtl/audio/v3_audio_system.v'}
 header_phase='wire header_late=(mstate==H_HEAD)'in(root/'safevision/rtl/media/bmp_parser.v').read_text('utf-8-sig')
 require(header_phase,'reviewed header phase not selected')
 allowed|={'safevision/rtl/media/bmp_parser.v','safevision/tools/gen_v3_cdc.py',str(FLOW/'v3_cdc.sdc').replace('\\','/'),str(FLOW/'v3_cdc_audit.tcl').replace('\\','/')}
 fs_registered='.REGISTERED_TIMEOUT_EDGE(FLEX_FILES)'in(root/'safevision/rtl/storage/v3_shared_fs_service.v').read_text('utf-8-sig')
 if fs_registered:allowed|={'safevision/rtl/storage/v3_file_streamer_compact_ctx.v','safevision/rtl/storage/v3_shared_fs_service.v'}
 checkpoint=(root/FLOW/'v3_implementation_checkpoint.tcl').is_file()
 if checkpoint:
  from v3_checkpoint_flow import validate
  require(validate(root)['accepted'],'checkpoint source transform differs')
  allowed.add('safevision/tools/run_v3_board.py')
 packed='.PACKED_EXTERNAL(1)'in top
 selected=top.count('.EXTERNAL_FONT(1)')==1 and top.count('.SHARED_TICKER(TICKER_ENABLE)')==1 and top.count('.SHARED_PACKED_FONT(TICKER_ENABLE)')==1 and top.count('.PACKED_EXTERNAL(1)')==1 and '.EXTERNAL_FONT(0)'not in top and '.SHARED_TICKER(0)'not in top if packed else top.count('.EXTERNAL_FONT(0)')==1 and top.count('.SHARED_TICKER(0)')==1 and '.EXTERNAL_FONT(1)'not in top and '.SHARED_TICKER(TICKER_ENABLE)'not in top
 require(selected and top.count('.MESSAGE_CHARS(32)')==1 and '.MESSAGE_CHARS(16)'not in top and '.WIDTH(HDMI_STATUS_W)'in top and '.PIXEL_LATENCY(5),.SOURCE_AHEAD(5),.CLIP_INPUT(0)'in top and 'b_query_group0 <= b_query_packed'in top and 'cmd_value==101||cmd_value==102'not in top,'32character/shared-status/lookahead/packed-reply production profile differs')
 production_profile=dict(font_storage='lossless_shared_fft_dp9'if packed else'dedicated_ram9k',message_characters=32,period_pixels=1024,fft_font_sharing=packed,video_latency_clocks=21,source_ahead_pixels=5)
 if checkpoint:production_profile.update(implementation_processes=2,serialized_synthesis_checkpoint=True)
 require('.REGISTERED_RESIDENT_READY(TICKER_ENABLE)'in top,'resident readiness profile not selected by the production flag')
 require(top.count('.SOURCE_PROGRESS_AWARE(TICKER_ENABLE)')==1 and top.count('source_progress_mem<={source_progress_mem[1:0],player_progress[0]};')==1 and top.count('source_byte_progress=source_progress_mem[2]^source_progress_mem[1]')==1 and '.source_progress(source_byte_progress)'in top,'production accepted-byte progress path differs')
 new={'safevision/rtl/video/v3_scrolling_ticker.v','safevision/assets/fonts/v3_ticker16.mem','safevision/assets/fonts/v3_ticker16.provenance.json'}|{str(FLOW/n).replace('\\','/')for n in ('ticker_enable.v','base/v3_ticker16.mem','hd/v3_ticker16.mem')}
 new|={'safevision/assets/fonts/v3_spectrum_ticker.mem','safevision/assets/fonts/v3_spectrum_ticker.provenance.json','safevision/assets/fonts/v3_ticker_shared16.mem'}|{str(FLOW/n).replace('\\','/')for n in ('base/v3_spectrum_ticker.mem','hd/v3_spectrum_ticker.mem')}
 if packed:new|={'safevision/assets/fonts/v3_spectrum_ticker32.mem','safevision/assets/fonts/v3_spectrum_ticker32.provenance.json','safevision/rtl/include/v3_ticker_packed32.vh','safevision/rtl/include/v3_ticker_byte32.vh','safevision/tools/build_ticker_shared32_lossless.py'}|{str(FLOW/n).replace('\\','/')for n in('base/v3_spectrum_ticker32.mem','hd/v3_spectrum_ticker32.mem')}
 new.add('safevision/tools/check_bmp_header_phase.py')
 if checkpoint:new|={'safevision/tools/v3_checkpoint_flow.py',str(FLOW/'v3_implementation_checkpoint.tcl').replace('\\','/')}
 require(set(old)<=set(sources)and set(sources)-set(old)==new,'unreviewed production dependency added/removed')
 changes={n for n,h in old.items()if sources[n]!=h}
 optional={str(FLOW/'v3_build_parameters_base.tcl').replace('\\','/')}
 optional|=layout_files
 require((allowed-optional)<=changes and changes<=allowed,'unexpected physical changes: '+repr((changes-allowed)|((allowed-optional)-changes)))
 if changes&layout_files:
  require(changes&layout_files==layout_files,'partial media-RAM layout/readback profile')
  from v3_sources import required_media_bram_locations
  locations=required_media_bram_locations(root,'base')
  expected={'player/normalized_bmp$u_unpack/ramread0_syn_5':'X8Y18Z0','player/normalized_bmp$u_unpack/ramread0_syn_15':'X8Y18Z1','row_guard/ramread0_syn_6':'X8Y9Z0','row_guard/ramread0_syn_23':'X8Y9Z1','sink/u_fifo/fifo/ram_inst/ramread0_syn_6':'X8Y18Z3','sink/u_fifo/fifo/ram_inst/ramread0_syn_16':'X8Y18Z2'}
  if len(locations)==45:
   reference=root/'safevision/verification/assets/bram_layout261028/route25.adc'
   require(sha(reference)=='ac2e2bd6056c95056a0c57668af7ef615525757a6b90310870f74c5696fe8dd4','native layout reference changed')
   full=dict(re.findall(r'set_inst_assignment \{([^}]+)\} \{LOCATION = ([^;]+);\}',reference.read_text('utf-8-sig')))
   require(len(full)==46 and set(expected)<=set(full),'reference native macro inventory differs')
   del full['scrolling$ticker/ramread0_syn_5']
   full['video/graphics/spectrum$analyzer/ramread0_syn_5']=full.pop('video/graphics/spectrum$analyzer/ramread0_syn_6')
   require(locations==full and len(set(full.values()))==45,'full shared-font macro layout differs from the verified reference')
  else:require(locations==expected,'reviewed BASE six-RAM layout differs')
  require(not required_media_bram_locations(root,'hd'),'HD layout changed')
  production_profile['base_media_bram_locations']=locations
 require(len(sources)==(224 if packed else 217)+int(header_phase)+2*int(checkpoint),'current physical inventory changed')
 summary=read(regression/'summary.json');require(summary.get('complete')and summary.get('accepted'),'full native campaign incomplete/failed')
 expected_jobs={('legacy','a'),('legacy','b')}|{('positive',r['top'])for r in matrix['positive']if not r['legacy']}|{('negative',r['mutation'])for r in matrix['negative']}
 require({(r['kind'],r['name'])for r in summary['records']}==expected_jobs,'native campaign inventory differs')
 checked=[]
 for case in matrix['positive']:
  top=case['top'];suite=case['suite']
  if case['legacy']:
   key='a'if suite=='legacy_a'else'b';base=regression/'legacy'/key/'native'
   record=read(base/'results.json');require(record['complete']and record['source_unchanged']and record['process_exit']==0,'legacy campaign failed')
   bind(root,base)
   log=base/'native'/top/'xsim.log'if key=='a'else base/'native'/(top+'_sim.log')
   raw=audit_file(log);require(raw['accepted'],'legacy raw failure: '+top)
  else:
   base=regression/'positive'/top;record=read(base/'result.json');require(record['status']=='PASS'and record['process_exit']==0,'positive native failure: '+top)
   folder=base/'native'/top;bind(root,folder);raw=audit_file(folder/'sim.log',True);require(raw['accepted'],'positive raw failure: '+top)
   graph(root,folder,dict(suite=suite,top=top))
  checked.append(dict(top=top,suite=suite,raw_sha256=raw['sha256']))
 negatives=[]
 for case in matrix['negative']:
  folder=regression/'negative'/case['mutation'];record=read(folder/'result.json')
  require(record['case']==case and record['status']=='PASS'and record['process_exit']==1 and record['normal_completion'],'negative case not an HDL detection')
  path=root/case['target'];require(sha(path)==record['original_sha256'],'negative original changed')
  text=path.read_text('utf-8-sig')
  for patch in case['patch']:
   require(text.count(patch['before'])==patch.get('occurrences',1),'negative patch count changed')
   text=text.replace(patch['before'],patch['after'])
  mutant=folder/'mutant.v';require(text==mutant.read_text('utf-8-sig')and sha(mutant)==record['mutated_sha256'],'negative mutant differs')
  native=folder/'native'/case['top'];bind(root,native,case['target'],record['mutated_sha256']);graph(root,native,dict(suite=case['suite'],top=case['top']),record)
  log=(native/'sim.log').read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  require('$finish called'in log and'[FAIL'in log and bool(re.search(r'PASS\s+'+re.escape(case['top'])+r'\b|\[TB\]\s*'+re.escape(case['top'])+r'\s+done',log)),'negative completion/detector absent')
  require(counts==record['error_counts']and any(counts),'negative errors absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log,'negative tool failure or skip')
  negatives.append(dict(name=case['mutation'],raw_sha256=sha(native/'sim.log')))
 additions=[]
 for suite,top,base in (('ticker261028','tb_v3_ticker_clip',ticker),('ticker261028','tb_v3_ticker_base',ticker),('ticker_board261028','tb_v3_ticker_board',board)):
  record=read(base/'results.json');require(record['complete'],'new positive suite incomplete')
  native=base/top;bind(root,native);raw=audit_file(native/'sim.log',True);require(raw['accepted'],'new positive raw failure')
  g=graph(root,native,dict(suite=suite,top=top));additions.append(dict(top=top,raw_sha256=raw['sha256'],compiler=g))
 control_summary=read(controls/'summary.json');require(control_summary['accepted']and len(control_summary['cases'])==15,'ticker controls incomplete')
 wanted={'frozen_phase','pixel_advance','early_wrap','mirrored_columns','one_clock_misalignment','overwrites_uptime','corrupted_rom_bit','wrong_production_id','bypassed_overlay','wrong_status_signature','media_reset_leaks','wrong_lookahead','premature_input_clip','packed_query_bank1_lost','packed_query_bank4_lost'}
 require({c['name']for c in control_summary['cases']}==wanted,'ticker control inventory changed')
 for case in control_summary['cases']:
  require(case['accepted']and case['process_exit']==1 and case['normal_completion'],'ticker control did not finish normally')
  folder=controls/case['name'];p=root/case['target'];require(sha(p)==case['original_sha256'],'ticker control source changed')
  text=p.read_text('utf-8-sig');require(text.count(case['before'])==1,'ticker control patch changed')
  require((folder/'mutant.v').read_text('utf-8-sig')==text.replace(case['before'],case['after'])and sha(folder/'mutant.v')==case['mutated_sha256'],'ticker control mutant changed')
  top='tb_v3_ticker_board'if'safevision_top/'in case['target']else'tb_v3_ticker_clip';suite='ticker_board261028'if top.endswith('board')else'ticker261028'
  native=folder/'native'/top;bind(root,native,case['target'],case['mutated_sha256']);graph(root,native,dict(suite=suite,top=top),case)
  log=(native/'sim.log').read_text('utf-8',errors='replace')
  counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in log and'PASS '+top in log and'[FAIL]'in log and counts==case['error_counts']and any(counts),'ticker detector raw evidence changed')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log,'ticker control crashed or skipped')
 # The resident handoff is terminal until media reset. Compare every public
 # player output against the unchanged original, including arbitrary contexts.
 resident=controls.parent/'resident';resident_controls=controls.parent/'resident_controls'
 rtop='tb_v3_resident_owner_equivalence';rsuite='resident_owner_equivalence261028'
 require(read(resident/'results.json')['complete'],'resident equivalence incomplete')
 native=resident/rtop;bind(root,native);raw=audit_file(native/'sim.log',True)
 require(raw['accepted'],'resident public-interface equivalence failed')
 additions.append(dict(top=rtop,raw_sha256=raw['sha256'],compiler=graph(root,native,dict(suite=rsuite,top=rtop))))
 rows=read(resident_controls/'summary.json');require(rows['accepted']and len(rows['cases'])==2,'resident error controls incomplete')
 require({c['name']for c in rows['cases']}=={'resident_gap_bypassed','resident_owner_bypassed'},'resident detector inventory differs')
 for case in rows['cases']:
  require(case['accepted']and case['process_exit']==1 and case['normal_completion'],'resident detector did not finish normally')
  folder=resident_controls/case['name'];path=root/case['target'];require(sha(path)==case['original_sha256'],'resident source changed')
  text=path.read_text('utf-8-sig');require(text.count(case['before'])==1,'resident detector patch differs')
  require((folder/'mutant.v').read_text('utf-8-sig')==text.replace(case['before'],case['after'])and sha(folder/'mutant.v')==case['mutated_sha256'],'resident mutant differs')
  native=folder/'native'/rtop;bind(root,native,case['target'],case['mutated_sha256']);graph(root,native,dict(suite=rsuite,top=rtop),case)
  log=(native/'sim.log').read_text('utf-8',errors='replace')
  counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in log and'[TB] '+rtop+' done'in log and'[FAIL]'in log and counts==case['error_counts']and any(counts),'resident raw detector missing')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log,'resident control crashed or skipped')
 shared=controls.parent/'shared';shared_controls=controls.parent/'shared_controls'
 stop='tb_v3_ticker_shared_port';ssuite='ticker_shared261028'
 original=subprocess.check_output(['git','-C',str(root),'cat-file','blob','09faac2e8fa718c9f92ef4a5013b68003ec8afe6:safevision/rtl/video/v3_audio_spectrum.v'])
 require(original.count(b'module v3_audio_spectrum #(')==1,'original FFT module ambiguous')
 require((root/'safevision/verification/models/v3_audio_spectrum_frozen261026.sv').read_bytes()==original.replace(b'module v3_audio_spectrum #(',b'module v3_audio_spectrum_frozen261026 #('),'frozen FFT reference changed beyond module name')
 require(read(shared/'results.json')['complete'],'shared font/FFT suite incomplete')
 native=shared/stop;bind(root,native);raw=audit_file(native/'sim.log',True);require(raw['accepted'],'shared font or frozen FFT comparison failed')
 additions.append(dict(top=stop,raw_sha256=raw['sha256'],compiler=graph(root,native,dict(suite=ssuite,top=stop)),role='alternate shared-font library configuration',production_selected=False))
 rows=read(shared_controls/'summary.json');require(rows['accepted']and len(rows['cases'])==3,'shared-port controls incomplete')
 require({c['name']for c in rows['cases']}=={'shared_font_wrong_address','shared_font_wrong_byte','shared_band_state_advance'},'shared-port detector inventory differs')
 for case in rows['cases']:
  require(case['accepted']and case['process_exit']==1 and case['normal_completion'],'shared-port detector did not finish normally')
  folder=shared_controls/case['name'];path=root/case['target'];require(sha(path)==case['original_sha256'],'shared-port source changed')
  text=path.read_text('utf-8-sig');require(text.count(case['before'])==1,'shared-port detector patch differs')
  require((folder/'mutant.v').read_text('utf-8-sig')==text.replace(case['before'],case['after'])and sha(folder/'mutant.v')==case['mutated_sha256'],'shared-port mutant differs')
  native=folder/'native'/stop;bind(root,native,case['target'],case['mutated_sha256']);graph(root,native,dict(suite=ssuite,top=stop),case)
  log=(native/'sim.log').read_text('utf-8',errors='replace')
  counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in log and'PASS '+stop in log and'[FAIL]'in log and counts==case['error_counts']and any(counts),'shared-port raw detector missing')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log,'shared-port control crashed or skipped')
 additions.append(positive(root,controls.parent/'shape_factor','shape_factor261028','tb_v3_shape_factor'))
 additions.append(positive(root,controls.parent/'geometry_stages','geometry_stages261028','tb_v3_geometry_stages'))
 geometry_controls=semantic_controls(root,controls.parent/'shape_controls','shape_factor261028','tb_v3_shape_factor',{'shape_width_factor_lost','shape_height_width_truncated'})
 geometry_controls+=semantic_controls(root,controls.parent/'geometry_controls','geometry_stages261028','tb_v3_geometry_stages',{'geometry_live_metadata','geometry_divisor_swapped'})
 numeric=numeric_shape(root,controls.parent/'shape_numeric')
 normalizer=(root/'safevision/rtl/media/v3_bmp_normalizer.v').read_text('utf-8-sig')
 require(normalizer.count('localparam GB=FLEX_PIXELS?SB+8:SB+XB;')==1 and normalizer.count('wire[GB-1:0] geometry_scratch={y_error,x_error};')==1 and 'localparam GB=FLEX_PIXELS?SB+10:SB+XB;'not in normalizer,'production geometry-width23 profile differs')
 width_proof=numeric_geometry_width(root,controls.parent/'geometry_width')
 require(len(additions)==7 and len({r['top']for r in additions})==7,'additional positive inventory changed')
 live_positive,live_control=live_geometry(root,controls.parent)
 wait_positive,wait_controls,wait_coverage=source_wait(root,controls.parent)
 additions+=[live_positive]+wait_positive
 require(len(additions)==12 and len({r['top']for r in additions})==12,'reviewed extended positive inventory changed')
 packed_controls=[];packed_proof=None
 if packed:
  extra,packed_controls,packed_proof=packed_font(root,controls.parent);additions+=extra
 pointer_proof=None;pointer_controls=[]
 if direct_pointer:
  extra,pointer_proof=pointer_compare(root,controls.parent);additions+=extra;pointer_controls=pointer_proof['semantic_controls']
  production_profile['audio_ring_direct_pointer_compare']=True
  production_profile['audio_ring_registered_occupancy']=pointer_proof['mathematical_proof']['registered_occupancy']
  production_profile['audio_ring_capacity_pairs_per_slot']=16384
 header_controls=[];header_proof=None
 if header_phase:
  extra,header_controls,header_proof=bmp_extent(root,controls.parent);additions+=extra
  production_profile['bmp_extent_sum_bits']=33;production_profile['bmp_extent_private_stages']=0;production_profile['bmp_header_phase']=[52,53];production_profile['bmp_header_setup_cycles']=2;production_profile['bmp_header_hold_cycles']=1;production_profile['bmp_publication_byte']=53
 fs_controls=[];fs_proof=None
 if fs_registered:
  extra,fs_controls,fs_proof=fs_timeout_pipeline(root,controls.parent);additions+=extra
  production_profile.update(fs_timeout_registered=True,fs_timeout_public_bits=322)
 direct_controls=[];direct_proof=None
 if direct_lookup:
  extra,direct_controls,direct_proof=direct_row_lookup(root,controls.parent);additions+=extra
  production_profile.update(direct_row_lookup=True,row_lookup_public_bits=233,row_lookup_descriptor_cases=4096,row_lookup_added_latency=0)
 decimal_controls=[];decimal_proof=None
 if decimal_reallocation:
  extra,decimal_controls,decimal_proof=decimal_dsp(root,controls.parent);additions+=extra
  production_profile.update(decimal_dsp_reallocation=True,decimal_accumulator_bits=24,decimal_public_bits=186,decimal_added_latency=0)
 request_proof=None
 if request_boundary:
  from check_audio_request_boundary import check as request_check
  request_proof=request_check(root)
  require(request_proof==read(controls.parent/'request_boundary_numeric/result.json')and request_proof['accepted']and request_proof['request_priority_cases']==64 and request_proof['verilog_operators_state_and_interface_unchanged']and request_proof['added_latency_cycles']==0 and not request_proof['clock_reset_constraints_changed'],'audio request complete-source/priority proof differs')
  production_profile['audio_request_boundary']=True
 compatibility=dict(production_selected=False,scope='Alternate16character shared-font library parameters; production retains the complete32character bitmap',positive_top=stop,semantic_controls=['shared_font_wrong_address','shared_font_wrong_byte','shared_band_state_advance'])
 return dict(accepted=True,physical_inputs=len(sources),production_profile=production_profile,production_changes=sorted(changes),production_additions=sorted(new),preserved_positive_tops=303,added_positive_tops=len(additions),total_positive_tops=303+len(additions),preserved_semantic_controls=221,added_semantic_controls=29+len(packed_controls)+len(pointer_controls)+len(header_controls)+len(fs_controls)+len(direct_controls)+len(decimal_controls),total_semantic_controls=250+len(packed_controls)+len(pointer_controls)+len(header_controls)+len(fs_controls)+len(direct_controls)+len(decimal_controls),positive=checked,negative=negatives,additions=additions,shared_port_compatibility=compatibility,packed_font_controls=packed_controls,packed_font_proof=packed_proof,audio_ring_pointer_proof=pointer_proof,bmp_header_pipeline_proof=header_proof,fs_timeout_pipeline_proof=fs_proof,direct_row_lookup_proof=direct_proof,decimal_dsp_proof=decimal_proof,audio_request_boundary_proof=request_proof,geometry_controls=geometry_controls,live_geometry_control=live_control,source_wait_controls=wait_controls,source_wait_coverage=wait_coverage,integer_domain=numeric,geometry_width=width_proof,source_sha256=sources,fresh_native_simulation=True,hardware_verified=False)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT)
 for key in ('regression','ticker','board','controls','output'):ap.add_argument('--'+key,type=Path,required=True)
 a=ap.parse_args()
 try:result=audit(a.repo.resolve(),a.regression,a.ticker,a.board,a.controls)
 except Exception as exc:result=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(result,indent=2)+'\n','utf-8');print('TICKER FUNCTIONAL AUDIT '+('PASS'if result['accepted']else'FAILED: '+result['error']))
 return 0 if result['accepted']else 1
if __name__=='__main__':sys.exit(main())
