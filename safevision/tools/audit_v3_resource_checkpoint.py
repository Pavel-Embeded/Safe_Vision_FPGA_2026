"""Portable audit of exact-source native functional evidence; no STA claim."""
import argparse,hashlib,json,re,sys
from pathlib import Path
from audit_v3_raw_logs import audit_file
ROOT=Path(__file__).resolve().parents[2]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def within(root,name):
 p=(root/name).resolve()
 if not p.is_relative_to(root.resolve()):raise ValueError('evidence/source path escaped root')
 return p

def sources(root,folder,negative=None):
 before=read(folder/'sources.sha256.json');assert before
 after=folder/'sources.after.sha256.json'
 if after.exists():assert read(after)==before,'source changed during test'
 changes=0
 for name,digest in before.items():
  assert re.fullmatch('[0-9a-f]{64}',digest)
  p=within(folder,name.split(':',1)[1]) if name.startswith('generated:') else within(root,name)
  if negative and digest==negative['mutated_sha256']:
   assert sha(p)==negative['original_sha256'],'negative baseline changed'
   assert sha(within(folder,negative['mutant_file']))==digest,'missing exact mutant bytes'
   changes+=1
  else:assert p.is_file() and sha(p)==digest,'current source/input differs: '+name
 if negative:assert changes==1,'negative source binding ambiguous'
 return len(before)

def audit(root,manifest):
 if not __debug__:raise RuntimeError('native acceptance audit requires Python assertions enabled')
 j=read(manifest);assert j['schema']==1 and j['complete']
 prior=read(root/'evidence/v3/current_100_20261016/selected_acceptance.json')
 required=set(prior['unique_tops'])|{'tb_v3_command_catalog','tb_v3_uart_link_catalog'}
 core=(root/'safevision/rtl/video/v3_video_display_core.v').read_text(encoding='utf-8')
 if 'v3_scaler_bilinear_thirds s' in core:required.add('tb_v3_thirds_scaler')
 reset=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v').read_text(encoding='utf-8')
 supervisor=(root/'safevision/rtl/control/v3_supervisor.v').read_text(encoding='utf-8')
 if 'RELEASE_FALLING' in reset:required.add('tb_v3_reset_release_phase')
 if 'reg[32:0] video_limit,audio_limit' in supervisor:required.add('tb_v3_supervisor_threshold')
 if 'begin:compare_byte' in supervisor:required.add('tb_v3_supervisor_comparator')
 audio=(root/'safevision/rtl/audio/v3_audio_system.v').read_text(encoding='utf-8')
 if 'v3_audio_prefill_compare #' in audio:required.add('tb_v3_audio_prefill_compare')
 top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text(encoding='utf-8')
 if 'v3_phy_reset_fanout reset_phy(' in top:required.update({'tb_v3_phy_reset_fanout','tb_v3_phy_lane_equivalence'})
 if 'B_QUERY_UARTDROP' in top:required.add('tb_v3_board_query_catalog')
 receiver=(root/'safevision/rtl/common/uart_rx.v').read_text(encoding='utf-8')
 controls=(root/'safevision/rtl/control/v3_user_controls.v').read_text(encoding='utf-8')
 if 'BOUNDED_ACC' in receiver:required.add('tb_v3_uart_rx_equivalence')
 if 'NAME_BRIGHT:' in controls:required.add('tb_v3_control_decode_equivalence')
 if 'decode_catalog(catalog_id)' in controls:required.add('tb_v3_control_catalog_equivalence')
 seen=set();rows=[]
 for row in j['positive_tests']:
  assert row['top'] not in seen;seen.add(row['top'])
  folder=within(root,row['evidence']);metadata=read(folder/'result.json')
  assert metadata['top']==row['top'] and metadata['accepted_native_runner'] and not metadata['source_overrides']
  assert sha(folder/'result.json')==row['result_sha256']
  count=sources(root,folder);raw=audit_file(folder/'sim.log',not row['legacy'])
  assert raw['accepted'],raw
  rows.append({'top':row['top'],'source_bindings_checked':count,'raw_log_sha256':raw['sha256']})
 assert seen==required,('required tests missing/extra',sorted(required-seen),sorted(seen-required))
 mutants=[]
 for row in j['negative_controls']:
  folder=within(root,row['evidence']);case=read(folder/'case.json')
  assert case['detected'] and case['normal_completion'];sources(root,folder,case)
  text=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
  assert '$finish called' in text and '[FAIL' in text
  assert re.search(r'PASS\s+'+re.escape(case['top'])+r'\b|\[TB\]\s*'+re.escape(case['top'])+r'\s+done',text)
  assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',text) and '[SKIP]' not in text
  values=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',text)]
  assert values==case['error_counts'] and any(values)
  if case.get('required_marker'):assert case['required_marker'] in text
  assert case['mutation'] not in mutants;mutants.append(case['mutation'])
 assert len(mutants)>=13
 if len(required)>=105:
  assert {'positive_phase_release','drop threshold carry33_to32','retimed_rounding','message_snapshot_bit'}.issubset(mutants),'new datapath/phase changes need their strict negative controls'
 if 'begin:compare_byte' in supervisor:
  assert {'lookahead_high_byte','tick_predict_off_by_one'}.issubset(mutants),'lookahead logic needs comparator and tick semantic mutants'
 if 'v3_audio_prefill_compare #' in audio:assert {'prefill_partial_weight','prefill_boundary'}.issubset(mutants),'prefill predicate needs semantic mutants'
 if 'v3_phy_reset_fanout reset_phy(' in top:assert {'phy_release_early','phy_lane_payload'}.issubset(mutants),'lane replication needs reset and serial-data mutants'
 if 'B_QUERY_UARTDROP' in top:assert 'board_query_binding' in mutants,'numeric board queries need binding corruption detection'
 if 'BOUNDED_ACC' in receiver:assert 'uart_fractional_step' in mutants,'bounded UART accumulator needs tick corruption detection'
 if 'NAME_BRIGHT:' in controls:assert {'control_signed_range','control_write_binding'}.issubset(mutants),'control decoding needs signed-boundary and write-binding mutants'
 if 'decode_catalog(catalog_id)' in controls:assert 'control_catalog_binding' in mutants,'board controls need an independently detected catalog-ID binding mutant'
 return {'accepted':True,'positive_unique_native_tests':len(required),'strict_normal_ending_mutants':len(mutants),'tests':rows,'source_bytes_and_inputs_verified':True,'routed_sta_passed':False,'bitstreams_verified':False,'hardware_verified':False,'release_ready':False}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--manifest',type=Path,default=Path('evidence/v3/resource_113_20261016/acceptance.json'));ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=audit(a.repo.resolve(),within(a.repo,a.manifest));code=0
 except Exception as ex:r={'accepted':False,'error':str(ex),'release_ready':False};code=1
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2),encoding='utf-8')
 print('RESOURCE CHECKPOINT '+('PASS' if r['accepted'] else 'FAIL'));return code
if __name__=='__main__':sys.exit(main())
