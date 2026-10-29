"""Approve BASE ticker bitgen from fresh complete HDL and routed evidence."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
from audit_ticker261028 import audit
from check_v3_board import check,read_report
from run_v3_board import source_commit_binding,invoke
from v3_sources import snapshot,check_gui
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text('utf-8-sig'))
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n','utf-8')
def require(ok,message):
 if not ok:raise ValueError(message)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--frozen-source',type=Path,required=True);ap.add_argument('--native-run',type=Path,required=True);ap.add_argument('--proof-root',type=Path,required=True);ap.add_argument('--archive',type=Path,required=True);ap.add_argument('--baseline-replay',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 root=a.repo.resolve();frozen=a.frozen_source.resolve();native=a.native_run.resolve();proof=a.proof_root.resolve();out=a.output.resolve()
 require(__debug__,'assertions disabled');require(str(out).isascii()and not out.exists()and not out.is_relative_to(root),'fresh isolated ASCII output required');out.mkdir(parents=True)
 result=dict(schema=1,profile='ticker261028',accepted=False,bitstreams_complete=False,expected_firmware_id='26102801',hardware_verified=False,flash_written=False,github_upload_performed=False)
 try:
  base=read(a.baseline_replay/'verification.json');require(base['accepted']and base['physical_inputs']==206 and base['positive_unique_tops']==303 and base['semantic_negative_controls']==221,'original qualification replay failed')
  for tool in ('test_ticker_archive261028.py','test_ticker_uart261028.py'):
   with(out/(tool+'.log')).open('w',encoding='utf-8')as log:
    code=subprocess.run([sys.executable,'-B',str(root/'safevision/tools'/tool)],cwd=root,stdout=log,stderr=subprocess.STDOUT).returncode
   require(code==0,'delivery evidence refusal tests failed: '+tool)
  functional=audit(root,proof/'regression',proof/'ticker',proof/'board',proof/'controls');save(out/'functional.audit.json',functional)
  if functional['production_profile'].get('base_media_bram_locations'):
   helper='test_v3_media_bram_layout261028.py';helper_temp=out/'helper_tmp';helper_temp.mkdir()
   helper_env=os.environ.copy();helper_env['TEMP']=helper_env['TMP']=str(helper_temp)
   with(out/(helper+'.log')).open('w',encoding='utf-8')as log:
    code=subprocess.run([sys.executable,'-B',str(root/'safevision/tools'/helper),'--repo',str(root),'--output',str(out/'media_bram.controls.json')],cwd=root,env=helper_env,stdout=log,stderr=subprocess.STDOUT).returncode
   require(code==0 and read(out/'media_bram.controls.json')['accepted']and read(out/'media_bram.controls.json')['check_count']==(26 if len(functional['production_profile']['base_media_bram_locations'])==45 else 13),'media RAM source/native-location detector tests failed')
  hardware=snapshot(root);require(snapshot(frozen)==hardware,'routed source differs from current hardware')
  record=read(native/'base/build.manifest.json');folder=native/'base'
  require(record['status']=='PASS'and record['source_unchanged']and record['source_commit_binding']['verified']and record['sources']==hardware,'native source identity rejected')
  design=source_commit_binding(root,root,record['source_commit'],hardware);require(design['verified'],'design commit mismatch')
  gate=check(folder,frozen);require(gate['gate_accepted']and gate['timing_passed']and gate['status']=='PASS','strict native timing gate failed: '+str(gate['errors']))
  save(out/'base.gate.json',gate)
  auto_native=None
  if functional['production_profile'].get('automatic_media_ram_placement'):
   from check_auto_ram_placement import check_native as auto_check_native
   auto_native=auto_check_native(root,folder);save(out/'automatic_ram.audit.json',auto_native)
   require(auto_native['accepted'],'automatic native RAM inventory failed')
   subprocess.run([sys.executable,'-B',str(root/'safevision/tools/test_auto_ram_placement.py'),'--source',str(frozen),'--output',str(out/'automatic_ram_controls')],check=True)
   auto_controls=read(out/'automatic_ram_controls/verification.json');require(auto_controls['accepted']and len(auto_controls['controls'])==7 and all(row['rejected']for row in auto_controls['controls']),'automatic RAM/pin/clock refusal controls failed')
  checkpoint_control=out/'source_profile_controls'
  subprocess.run([sys.executable,'-B',str(root/'safevision/tools/test_v3_checkpoint_profile.py'),'--source',str(frozen),'--native',str(folder),'--output',str(checkpoint_control)],check=True)
  checkpoint_verdict=read(checkpoint_control/'verification.json')
  require(checkpoint_verdict['accepted']and len(checkpoint_verdict['controls'])==7 and all(row['rejected']for row in checkpoint_verdict['controls']),'native source-order/checkpoint controls failed')
  subprocess.run([sys.executable,'-B',str(root/'safevision/tools/test_ticker_rom261028.py'),'--netlist',str(folder/'gate.netlist.v'),'--repo',str(root),'--output',str(out/'rom.controls.json')],check=True)
  rom=read(out/'rom.controls.json');require(rom['accepted']and len(rom['controls'])==5 and all(c['rejected']for c in rom['controls']),'mapped ROM rejection controls failed')
  # The original full gate and original absolute path attestations are kept.
  # Rechecking uses the unchanged real routed directory, not a reconstructed DB.
  protected={Path(row['path']):row['sha256']for row in gate['reports']}
  protected[folder/'build.manifest.json']=sha(folder/'build.manifest.json')
  if auto_native:protected[folder/'route.bram.adc']=auto_native['ram_readback_sha256']
  for p,digest in protected.items():require(p.resolve().is_relative_to(folder.resolve())and sha(p)==digest,'native evidence changed')
  exe=Path(record['td_executable']);require(sha(exe)==record['td_executable_sha256'],'TD executable changed')
  names=set(hardware)
  for p in proof.rglob('sources.sha256.json'):
   names.update(name for name in read(p)if not name.startswith('generated:'))
  names|={'safevision/tools/audit_ticker261028.py','safevision/tools/ticker_evidence_archive.py','safevision/tools/finalize_ticker261028.py','safevision/tools/test_ticker_rom261028.py','safevision/tools/build_ticker_font.py','safevision/tools/host/exercise_ticker261028.ps1',a.archive.resolve().relative_to(root).as_posix()}
  names|={'safevision/tools/audit_ticker_uart261028.py','safevision/tools/verify_ticker_ci.py','safevision/tools/replay_ticker_native261028.py','safevision/tools/ticker_host_profile261028.py','safevision/tools/check_ticker_offline261028.py'}
  names.add('safevision/tools/host/burn_ticker261028_sram.ps1')
  names.add('safevision/tools/test_v3_checkpoint_profile.py')
  names|={'safevision/tools/build_ticker_shared_font.py','safevision/tools/check_shape_space261028.py'}
  if functional.get('packed_font_proof'):
   names|={'safevision/tools/build_ticker_shared32_lossless.py','safevision/tools/test_lossless_shared32_controls.py','safevision/verification/models/v3_scrolling_ticker_frozen_packed32.freeze.json','safevision/verification/models/v3_scrolling_ticker_frozen_packed32.sv'}
  if functional.get('audio_ring_pointer_proof'):
   names|={'safevision/tools/check_ring_pointer_compare.py','safevision/tools/test_ring_pointer_controls.py','safevision/verification/models/v3_pcm_ring_frozen_pointer.freeze.json','safevision/verification/models/v3_pcm_ring_frozen_pointer.sv'}
  names|={'safevision/tools/test_ticker_archive261028.py','safevision/tools/test_ticker_uart261028.py'}
  names|={'safevision/tools/test_geometry_live_miter261028.py','safevision/tools/test_source_wait_watchdog261028.py','safevision/tools/check_v3_legacy_ports537.py'}
  if functional['production_profile'].get('base_media_bram_locations'):
   names|={'safevision/tools/test_v3_media_bram_layout261028.py','safevision/verification/assets/bram_layout261028/route25.adc','safevision/verification/assets/bram_layout261028/place45.adc','safevision/verification/assets/bram_layout261028/provenance.json'}
  if functional['geometry_width'].get('accepted'):
   names.add('safevision/tools/check_geometry_width261028.py')
  if functional['production_profile'].get('bmp_header_phase'):
   names|={'safevision/tools/check_bmp_header_phase.py','safevision/tools/test_bmp_header_phase_controls.py','safevision/verification/models/bmp_parser_frozen_extent.freeze.json'}
  if functional['production_profile'].get('fs_timeout_registered'):
   names|={'safevision/tools/check_fs_timeout_pipeline.py','safevision/tools/test_fs_timeout_controls.py','safevision/verification/models/v3_file_streamer_frozen_timeout.freeze.json'}
  if functional['production_profile'].get('direct_row_lookup'):
   names|={'safevision/tools/check_direct_row_lookup.py','safevision/tools/test_direct_row_controls.py','safevision/verification/models/direct_row_lookup112.freeze.json'}
  if functional['production_profile'].get('decimal_dsp_reallocation'):
   names|={'safevision/tools/check_decimal_dsp.py','safevision/tools/check_decimal_dsp_exhaustive.py','safevision/tools/test_decimal_dsp_controls.py','safevision/verification/models/decimal_dsp135.freeze.json'}
  if functional['production_profile'].get('audio_request_boundary'):
   names.add('safevision/tools/check_audio_request_boundary.py')
  if functional['production_profile'].get('registered_prefill_admission'):
   names|={'safevision/tools/check_prefill_pipeline.py','safevision/tools/test_prefill_pipeline_controls.py'}
  if functional.get('dedicated_font_proof'):
   names.add('safevision/tools/check_dedicated_font.py')
  if functional['production_profile'].get('automatic_media_ram_placement'):
   names|={'safevision/tools/check_auto_ram_placement.py','safevision/tools/test_auto_ram_placement.py'}
  commit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD']).decode().strip()
  binding=source_commit_binding(root,root,commit,names);require(binding['verified'],'approval inputs are not committed: '+str(binding.get('errors')))
  all_inputs={name:sha(root/name)for name in names}
  def unchanged():
   require(snapshot(root)==hardware and snapshot(frozen)==hardware,'production changed during bitgen')
   require(all(sha(root/name)==digest for name,digest in all_inputs.items()),'approval input changed during bitgen')
   require(all(sha(p)==digest for p,digest in protected.items()),'routed proof changed during bitgen')
   require(sha(exe)==record['td_executable_sha256'],'TD executable changed during bitgen')
  unchanged();pending=out/'base.pending.bit';tcl=out/'base.bitgen.tcl'
  tcl.write_text('if {[catch {\n import_db {'+(folder/'route.db').as_posix()+'}\n bitgen -bit {'+pending.as_posix()+'}\n export_bitgen_param -file {'+(out/'base.bitgen.params').as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "V3 BITGEN COMPLETE"\nexit 0\n','ascii')
  code,text=invoke(exe,tcl,out/'base.bitgen.console.log',os.environ.copy())
  require(code==0 and'V3 BITGEN COMPLETE'in text and pending.is_file()and pending.stat().st_size>0,'native bitgen incomplete');unchanged()
  bit=out/('SafeVision_BASE_'+record['source_commit'][:7]+'.bit');pending.replace(bit)
  result.update(accepted=True,bitstreams_complete=True,production_profile=functional['production_profile'],approval_source_commit=commit,design_build_commit=record['source_commit'],source_commit_binding=binding,source_sha256=hardware,approval_inputs_sha256=all_inputs,evidence_archive=a.archive.resolve().relative_to(root).as_posix(),evidence_archive_sha256=sha(a.archive),baseline_replay_sha256=sha(a.baseline_replay/'verification.json'),native_manifest_sha256=sha(folder/'build.manifest.json'),native_gate_sha256=sha(out/'base.gate.json'),functional_audit_sha256=sha(out/'functional.audit.json'),native_parameters=record['native_parameters'],td_version=record['td_version'],td_executable_sha256=record['td_executable_sha256'],route_database_sha256=sha(folder/'route.db'),bitstream=bit.name,bit_sha256=sha(bit),bit_bytes=bit.stat().st_size,bitgen_script_sha256=sha(tcl),bitgen_console_sha256=sha(out/'base.bitgen.console.log'),bitgen_parameters_sha256=sha(out/'base.bitgen.params'))
 except Exception as exc:result['error']=type(exc).__name__+': '+str(exc)
 save(out/'release.index.json',result);print('TICKER FINALIZATION '+('PASS'if result['accepted']else'REJECTED: '+result['error']),flush=True)
 return 0 if result['accepted']else 1
if __name__=='__main__':sys.exit(main())
