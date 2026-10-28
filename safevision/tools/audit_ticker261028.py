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
 native=base/top;bind(root,native);raw=audit_file(native/'sim.log',True)
 require(raw['accepted'],'additional positive raw failure: '+top)
 return dict(top=top,raw_sha256=raw['sha256'],compiler=graph(root,native,dict(suite=suite,top=top)))

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
 top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text('utf-8-sig')
 require(top.count('.MESSAGE_CHARS(32)')==1 and top.count('.EXTERNAL_FONT(0)')==1 and top.count('.SHARED_TICKER(0)')==1 and '.MESSAGE_CHARS(16)'not in top and '.EXTERNAL_FONT(1)'not in top and '.SHARED_TICKER(TICKER_ENABLE)'not in top and '.WIDTH(HDMI_STATUS_W)'in top and '.PIXEL_LATENCY(5),.SOURCE_AHEAD(5),.CLIP_INPUT(0)'in top and 'b_query_group0 <= b_query_packed'in top and 'cmd_value==101||cmd_value==102'not in top,'local32/shared-status/lookahead/packed-reply production profile differs')
 production_profile=dict(font_storage='dedicated_ram9k',message_characters=32,period_pixels=1024,fft_font_sharing=False,video_latency_clocks=21,source_ahead_pixels=5)
 require('.REGISTERED_RESIDENT_READY(TICKER_ENABLE)'in top,'resident readiness profile not selected by the production flag')
 new={'safevision/rtl/video/v3_scrolling_ticker.v','safevision/assets/fonts/v3_ticker16.mem','safevision/assets/fonts/v3_ticker16.provenance.json'}|{str(FLOW/n).replace('\\','/')for n in ('ticker_enable.v','base/v3_ticker16.mem','hd/v3_ticker16.mem')}
 new|={'safevision/assets/fonts/v3_spectrum_ticker.mem','safevision/assets/fonts/v3_spectrum_ticker.provenance.json','safevision/assets/fonts/v3_ticker_shared16.mem'}|{str(FLOW/n).replace('\\','/')for n in ('base/v3_spectrum_ticker.mem','hd/v3_spectrum_ticker.mem')}
 require(set(old)<=set(sources)and set(sources)-set(old)==new,'unreviewed production dependency added/removed')
 changes={n for n,h in old.items()if sources[n]!=h}
 optional={str(FLOW/'v3_build_parameters_base.tcl').replace('\\','/')}
 require((allowed-optional)<=changes and changes<=allowed,'unexpected physical changes: '+repr((changes-allowed)|((allowed-optional)-changes)))
 require(len(sources)==217,'current physical inventory changed')
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
 compatibility=dict(production_selected=False,scope='Alternate shared-font library parameters; the production local32 path uses a dedicated font ROM',positive_top=stop,semantic_controls=['shared_font_wrong_address','shared_font_wrong_byte','shared_band_state_advance'])
 return dict(accepted=True,physical_inputs=217,production_profile=production_profile,production_changes=sorted(changes),production_additions=sorted(new),preserved_positive_tops=303,added_positive_tops=7,total_positive_tops=310,preserved_semantic_controls=221,added_semantic_controls=24,total_semantic_controls=245,positive=checked,negative=negatives,additions=additions,shared_port_compatibility=compatibility,geometry_controls=geometry_controls,integer_domain=numeric,geometry_width=width_proof,source_sha256=sources,fresh_native_simulation=True,hardware_verified=False)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT)
 for key in ('regression','ticker','board','controls','output'):ap.add_argument('--'+key,type=Path,required=True)
 a=ap.parse_args()
 try:result=audit(a.repo.resolve(),a.regression,a.ticker,a.board,a.controls)
 except Exception as exc:result=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(result,indent=2)+'\n','utf-8');print('TICKER FUNCTIONAL AUDIT '+('PASS'if result['accepted']else'FAILED: '+result['error']))
 return 0 if result['accepted']else 1
if __name__=='__main__':sys.exit(main())
