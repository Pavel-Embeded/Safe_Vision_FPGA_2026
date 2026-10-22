"""Recheck archived source, actual functional evidence and raw routed STA.

This verifier performs no build, programming, network write or hardware claim.
Absolute paths in the immutable native receipt are mapped to archived bytes;
the original receipt and reports are never rewritten to make them pass.
"""
from pathlib import Path
import argparse,hashlib,json,re,sys
sys.dont_write_bytecode=True
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def safe(root,name):
 p=(root/name).resolve();assert p.is_relative_to(root),name;return p
def verify(root,repository):
 if not __debug__:raise RuntimeError('verification requires assertions enabled')
 index=read(root/'release.index.json');approval=read(root/'approval.index.json')
 assert index['profile']=='four_features_261020'and index['offline_acceptance_passed']
 assert approval['accepted']and approval['bitstreams_complete']and approval['requested_modes']==['base']
 assert approval['engineering_candidate']and not approval['two_mode_release']
 assert index['approval_source_commit']==approval['approval_source_commit']and index['design_build_commit']==approval['design_build_commit']
 assert index['expected_firmware_id']==approval['expected_firmware_id']=='26102004'
 assert sha(root/'approval.index.json')==index['approval_index_sha256']
 for name,digest in index['payload_sha256'].items():assert sha(safe(root,name))==digest,name
 source=root/'source';sys.path.insert(0,str(source/'safevision/tools'))
 from v3_sources import snapshot,sources,FLOW,native_parameters
 from native_git_binding import source_commit_binding
 from v3_functional_release import unchanged
 from audit_v3_four_features import audit
 from check_board_timing import assess,read_report
 from check_v3_board import resource_gate,clock_definition_health,exception_timing,exception_paths,constraint_objects,no_delay_ports
 from v3_resource_policy import load
 from check_v3_rom_netlist import check_roms
 from check_v3_board_reference import check as physical_board_check
 from check_v3_sample_netlist import check as sample_check
 from check_v3_spi_timing import check_cs
 from check_v3_io_scope import bounded_outputs,dead_ddc_input
 assert snapshot(source)==approval['source_sha256']and len(approval['source_sha256'])==198
 assert unchanged(source,approval['proof_sha256'])
 binding=source_commit_binding(source,repository,approval['approval_source_commit'],{**approval['source_sha256'],**approval['proof_sha256']});assert binding['verified'],binding.get('errors')
 functional=audit(source,Path('evidence/v3/four_features_261020/acceptance.json'),repository)
 assert functional['accepted']and functional['positive_unique_tops']==290 and functional['strict_normal_ending_mutants']==205
 assert functional['proof_sha256']==approval['proof_sha256']and functional['source_build_commit']==approval['design_build_commit']
 assert len(index['modes'])==1
 for row in index['modes']:
  mode=row['mode'];assert mode=='base';folder=root/'native'/mode;gate=read(folder/'timing.gate.json');build=read(folder/'build.manifest.json')
  assert gate['gate_accepted']and gate['timing_passed']and gate['status']=='PASS'
  assert build['status']=='PASS'and build['sources']==approval['source_sha256']and build['source_unchanged']and build['source_commit_binding']['verified']
  assert build['source_commit']==approval['design_build_commit']
  for report in gate['reports']:assert sha(folder/Path(report['path']).name)==report['sha256']
  timing=read_report(folder/'route.timing');health=read_report(folder/'route.check');exc=read_report(folder/'route.exceptions')
  sta=assess(timing,health);assert sta['gate_accepted']and sta['timing_passed'],sta['errors']
  assert not clock_definition_health(health)
  pins=physical_board_check(source,read_report(folder/'route.area'));assert pins['physical_pad_table_checked']and pins['physical_key_contract']==gate['board_reference']['physical_key_contract']
  resources=resource_gate(read_report(folder/'route.area'),load(source));assert resources['accepted'],resources['errors']
  assert resources['resources']==gate['resources']
  assert native_parameters(source,folder)==gate['native_parameters']
  check_roms(read_report(folder/'gate.netlist.v'),source);sample_check(read_report(folder/'route.netlist.v'))
  assert check_cs(timing)['accepted']
  assert exception_timing(exc)['accepted']
  budget=read(source/FLOW/'io_budget.json')
  assert bounded_outputs(exc,budget['asynchronous_bounded_output_ports'])['accepted']
  assert dead_ddc_input(read_report(folder/'gate.netlist.v'))['accepted']
  missing_in=set(no_delay_ports(health,'input'));missing_out=set(no_delay_ports(health,'output'))
  assert not missing_in-set(budget['asynchronous_input_ports'])-set(budget['vendor_absent_input_ports'])
  assert not missing_out-set(budget['forwarded_or_vendor_serial_output_ports'])-set(budget['asynchronous_bounded_output_ports'])-set(budget['vendor_open_drain_output_ports'])
  sdc=[(source/FLOW/n).read_text(encoding='utf-8-sig')for n in ('v3_board.sdc','v3_cdc.sdc')]
  _,errors=exception_paths(exc,sdc,mid_ref=budget['sd'].get('miso_sample_edge')=='falling_ref');assert not errors,errors
  _,errors=constraint_objects((folder/'constraint.objects.tsv').read_text(encoding='utf-8-sig'),(source/FLOW/'v3_cdc_audit.tcl').read_text(encoding='utf-8-sig'));assert not errors,errors
  integrity=read(folder/'final_sta.manifest.json');assert integrity['accepted']and integrity['normal_completion']and integrity['caller_route_process_exit_code']==integrity['sta_process_exit_code']==0
  before=integrity['database_and_constraint_sha256_before'];after=integrity['database_and_constraint_sha256_after'];assert before==after
  assert len(after)==4
  expected={str(Path(row['original_native_folder'])/'route.db'):folder/'route.db'}
  for n in ('v3_board.sdc','v3_cdc.sdc','v3_cdc_audit.tcl'):expected[str(Path(row['original_native_source'])/FLOW/n)]=source/FLOW/n
  assert set(after)==set(expected)
  for name,path in expected.items():assert after[name]==sha(path)
  assert integrity['reported_path_signature_unchanged']and integrity['actual_exception_commands_and_counts_unchanged']
  console=(folder/'native.console.log').read_text(encoding='utf-8',errors='replace')
  assert sha(folder/'native.console.log')==gate['native_ordered_source_profile']['native_log_sha256']
  matches=re.findall(r'^RUN-1002 : start command "read_hdl -file (.*?) -include_dir [^\r\n]*? -top safevision_v3_top"$',console,re.M);assert len(matches)==1
  expected=[str((Path(row['original_native_source'])/n).resolve()).casefold()for n in sources(source,mode)]
  assert [str(Path(n).resolve()).casefold()for n in matches[0].split()]==expected
  bit=safe(root,row['bitstream']);assert sha(bit)==row['bit_sha256']and bit.stat().st_size==row['bytes']
  original=next(r for r in approval['bitstreams']if r['mode']==mode)
  assert original['sha256']==row['bit_sha256']and original['route_database_sha256']==sha(folder/'route.db')
 return dict(accepted=True,profile=index['profile'],expected_firmware_id=index['expected_firmware_id'],approval_source_commit=approval['approval_source_commit'],positive_unique_tops=290,negative_controls=205,modes=['base'],two_mode_release=False,hardware_verified=False,github_uploaded=False)
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source-repo',type=Path);ap.add_argument('--output',type=Path);a=ap.parse_args();root=Path(__file__).resolve().parent
 repository=a.source_repo
 if repository is None:repository=next((p for p in root.parents if(p/'.git').exists()),None)
 if repository is None:raise ValueError('Pass --source-repo to the project Git repository containing the approval commit')
 result=verify(root,repository.resolve())
 if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print('PAYLOAD / 290 TESTS / 205 CONTROLS / SOURCE / RAW ROUTED STA PASS; hardware separate',flush=True)
 return 0
if __name__=='__main__':sys.exit(main())
