"""Mandatory declaration/HFN guard archive, preserving original3/24 controls.

Replays unchanged native captures and all17 additional bus/clone controls with
the current source checker. This module cannot approve STA or hardware.
"""
from pathlib import Path
import hashlib,importlib,json

RAW=('gate.netlist.v','route.netlist.v','route.clocks')
CHECKERS=('check_v3_clock_contract.py','check_v3_native_clock_domains.py','check_v3_native_clock_selftest.py')
SUPPORT=('check_v3_native_clock_replica_selftest.py','audit_v3_native_clock_archive_894.py')
FOCUSED={
 'unchanged_real_positive','gate_high_clock_mem50','gate_packet_clock_write100','route_high_clock_mem50','route_packet_clock_write100',
 'gate_ram_write_mem50','route_ram_write_mem50','xml_high_clock_missing','xml_high_wrong_clock_owner','xml_ram_write_missing',
 'xml_ram_write_wrong_clock_owner','xml_write100_zero_endpoints','xml_write100_frequency_drift','xml_duplicate_clock',
 'actual_external_reset_missing','base_control_wrong_pll_output','packed_present_but_scope_disabled','nonpacked_bounded_not_applicable',
 'gate_pll_phase_relationship_drift','gate_missing_packet_q','unchanged_bad_real_capture','actual_configured_clock_contract',
 'explicit_write_clock_replaced_by_mem50','explicit_reset_synchronizer_mem50','core_external_clock_bypassed',
 'core_external_reset_bypassed','physical_sys_clock_replaced_by_pll100_in_base'}
ACCEPTS={'unchanged_real_positive','nonpacked_bounded_not_applicable','actual_configured_clock_contract'}
BUS_ACCEPTS={'real883_bare_bus','equivalent_explicit_slice','equivalent_explicit_concat'}
BUS_REJECTS={'route_bus_bit1_lost','route_duplicate_Q_bit','route_bus_declaration_missing','route_bus_width_shrunk',
 'route_reset_bus_wrong_MEM50_clock','gate_reset_bit_wrong_MEM50_clock','xml_reset_bus_wrong_owner','xml_reset_bus_missing_endpoint',
 'sys_clone_Q_missing','sys_clone_wrong_WRITE100_clock','sys_clone_wrong_preceding_data','sys_clone_wrong_async_reset',
 'sys_clone_wrong_XML_clock','sys_clone_XML_missing'}

def require(ok,message):
    if not ok:raise ValueError('native clock archive: '+message)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def inside(root,name):
    path=(root/name).resolve()
    require(not Path(name).is_absolute()and path.is_relative_to(root.resolve())and path.is_file(),'missing/escaping file '+name)
    return path

def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))

def audit(root,folder):
    root,folder=Path(root).resolve(),Path(folder).resolve();receipt=read(inside(folder,'receipt.json'))
    require(receipt.get('schema')==2 and receipt.get('complete')is True and receipt.get('accepted')is True,'new complete schema2 required')
    require(receipt.get('focused_positive')==3 and receipt.get('focused_expected_rejections')==24,'original3/24 controls were weakened')
    require(receipt.get('bus_hfn_positive')==3 and receipt.get('bus_hfn_expected_rejections')==14,'new3/14 controls missing')
    require(receipt.get('native883_clock_bindings_per_stage')==dict(gate=60,route=74)and receipt.get('native883_sys_stage1_replicas')==15,'all actual883 SYS replicas required')
    require(receipt.get('native852_timing_signed_off')is False and receipt.get('native883_overall_reclassified')is False,'historical failures were reclassified')
    require(receipt.get('hardware_verified')is False and receipt.get('bitstream_approved')is False,'clock proof exceeds its scope')
    for name,digest in receipt['files'].items():require(sha(inside(folder,name))==digest,'evidence changed '+name)
    for name in CHECKERS+SUPPORT:
        require(sha(inside(folder,'checker_sources/'+name))==sha(inside(root,'safevision/tools/'+name)),'current checker/support source mismatch '+name)
    inputs=read(inside(folder,'source_inventory.json'))
    require(inputs.get('configured_source_sha256'),'fresh configured-source controls have no input binding')
    for name,digest in inputs['configured_source_sha256'].items():
        require(sha(inside(root,name))==digest==sha(inside(folder,'configured_source_inputs/'+name)),'configured-source control input differs '+name)
    history=read(inside(folder,'history.original.sha256.json'))
    require(history.get('complete_original_archive_preserved')is True and history.get('files'),'original complete archive history missing')
    for name,digest in history['files'].items():require(sha(inside(folder,'history_before_declaration_hfn_261023/'+name))==digest,'historical bytes changed '+name)
    focused=read(inside(folder,'focused.rerun.json'))
    require(focused.get('accepted')is True and focused.get('complete')is True and len(focused.get('results',[]))==27,'fresh original controls incomplete')
    require(focused.get('positive_cases')==3 and focused.get('expected_rejections')==24,'fresh original counts differ')
    require({x['case']for x in focused['results']}==FOCUSED,'original control definitions missing or duplicated')
    require(all(x['expected_reject']==(x['case']not in ACCEPTS)and x['rejected']==x['expected_reject']for x in focused['results']),'original normal rejection differs')
    domains=importlib.import_module('check_v3_native_clock_domains')
    require(sha(Path(domains.__file__))==sha(root/'safevision/tools/check_v3_native_clock_domains.py'),'wrong checker loaded')
    captures=[]
    for name,external,sys_output,expected in [('native734',False,0,True),('native803',False,1,False),('native852',True,1,True),('native883',True,1,True),('native892',True,1,True)]:
        base=folder/name/'base';data=[inside(base,n).read_text(encoding='utf-8')for n in RAW];error=None;result=None
        try:result=domains.check_texts(*data,packed=True,external_reset=external,sys_output=sys_output)
        except ValueError as ex:error=str(ex)
        require(bool(error)!=expected,'native capture acceptance differs '+name)
        recorded=read(inside(folder,name+'.rerun.json'))
        require(recorded.get('accepted')==expected and recorded.get('expected_accept')==expected,'native replay receipt differs '+name)
        require(recorded.get('raw_sha256')=={n:sha(base/n)for n in RAW},'native replay raw inputs differ '+name)
        if expected:
            require(result['accepted']and not result['hardware_verified']and not result['timing_signoff_by_this_check'],'invalid native replay scope')
            if name=='native883':require({k:len(v)for k,v in result['physical_stages'].items()}==dict(gate=60,route=74),'barebus/all-clone actual bindings differ')
        captures.append(dict(name=name,accepted=expected,bindings={k:len(v)for k,v in result['physical_stages'].items()}if result else None))
    bus=read(inside(folder,'bus_hfn.rerun.json'))
    require(bus.get('accepted')is True and bus.get('complete')is True and len(bus.get('results',[]))==17,'bus/HFN cohort incomplete')
    require(bus.get('bare_bus_positive')==3 and bus.get('bare_bus_and_SYS_clone_expected_rejections')==14,'bus/HFN counts differ')
    require({x['case']for x in bus['results']}==BUS_ACCEPTS|BUS_REJECTS,'bus/HFN definitions changed')
    require(all(x['expected_reject']==(x['case']in BUS_REJECTS)and x['expected_reject']==x['rejected']for x in bus['results']),'bus/HFN outcomes differ')
    require(bus.get('actual_native883_bindings')==dict(gate=60,route=74)and bus.get('validated_SYS_stage1_replicas')==15 and bus.get('actual_same_slice_independent_Q_bits')==[0,1],'actual declaration/replica proof missing')
    exercise=importlib.import_module('check_v3_native_clock_replica_selftest').exercise
    fresh=exercise(folder/'native883/base')
    for key in ('results','bare_bus_positive','bare_bus_and_SYS_clone_expected_rejections','actual_native883_bindings','validated_SYS_stage1_replicas','actual_same_slice_independent_Q_bits','inputs','checker_sha256'):
        require(fresh[key]==bus[key],'fresh current-parser bus/HFN controls differ '+key)
    gate=read(inside(folder,'native892/timing.gate.original.json'))
    require(gate.get('status')=='PASS'and gate.get('gate_accepted')is True and gate.get('timing_passed')is True and not gate.get('errors'),'new892 actual overall native gate is not PASS')
    frozen=read(inside(folder,'native892/design.original.json'))
    from v3_sources import snapshot
    require(len(frozen['physical_source_sha256'])==206 and snapshot(root)==frozen['physical_source_sha256'],'new892 native source206 differs from current source')
    manifest=read(inside(folder,'native892/build.manifest.original.json'))
    require(manifest.get('status')=='PASS'and manifest.get('source_unchanged')is True,'current actual native build did not complete unchanged')
    require(manifest.get('source_commit')==frozen['commit']and manifest.get('sources')==frozen['physical_source_sha256'],'new892 actual source/commit differs')
    binding=manifest.get('source_commit_binding',{})
    require(binding.get('verified')is True and binding.get('dependencies_compared')==206 and not binding.get('errors'),'actual new892 Git source binding missing')
    require(manifest.get('gate',{}).get('gate_accepted')is True,'actual manifest overall gate rejected')
    signoff=read(inside(folder,'native892/signoff.original.json'))
    require(signoff.get('accepted')is True and signoff.get('complete')is True and signoff.get('source_commit')==frozen['commit']and signoff.get('physical_sha256')==frozen['physical_source_sha256']and signoff.get('normal_native_exit')==0,'independent892 signoff missing')
    for name in RAW:require(signoff['original_native_reports_sha256'][name]==sha(folder/'native892/base'/name),'signed native raw input changed '+name)
    for name,relative in [('timing.gate.json','native892/timing.gate.original.json'),('build.manifest.json','native892/build.manifest.original.json')]:
        require(signoff['original_native_reports_sha256'][name]==sha(folder/relative),'signed native approval input changed '+name)
    for name,digest in signoff['independent_process_results'].items():
        require(sha(inside(folder,'native892/'+name))==digest,'independent gate changed '+name)
    old=read(inside(folder,'native883/timing.gate.original.json'))
    require(old.get('status')=='FAIL'and old.get('gate_accepted')is False and old.get('sta',{}).get('status')=='PASS','original883 parser failure was not retained')
    return dict(accepted=True,original_positive=3,original_refusals=24,bus_hfn_positive=3,bus_hfn_refusals=14,
                actual_native_replays=captures,all_15_SYS_replicas_replayed=True,historical_failures_preserved=True,
                current_native892_gate_independently_passed=True,STA_signoff_by_this_audit=False,hardware_verified=False,bitstream_approved=False)
