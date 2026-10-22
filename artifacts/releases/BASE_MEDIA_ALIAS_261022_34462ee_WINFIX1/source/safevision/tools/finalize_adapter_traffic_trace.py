"""Publish only the crossed-adapter diagnostic after exact simulation/STA gates.

Does not push GitHub. A diagnostic bitstream is not production acceptance.
"""
import argparse, hashlib, json, os, re, shutil, sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'safevision/tools'))
from check_board_timing import assess, read_report
from run_v3_board import source_commit_binding, invoke

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,x):p.write_bytes((json.dumps(x,indent=2,ensure_ascii=False)+'\n').encode('utf-8'))

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--native-run',type=Path,required=True)
    ap.add_argument('--sim-run',type=Path,required=True)
    ap.add_argument('--source-ref',required=True)
    ap.add_argument('--controls-root',type=Path,required=True)
    a=ap.parse_args();native=a.native_run.resolve();sim=a.sim_run.resolve()
    controls=a.controls_root.resolve()
    project='safevision/platform/anlogic_eg4s20_hx4s20c/project/adapter_traffic_26101725/'
    deps={}
    record=read(native/'native.acceptance.json')
    for name,digest in record['source_sha256'].items():
        key=project+name if name in ('probe.adc','probe.sdc') else name
        assert sha(ROOT/key)==digest,key;deps[key]=digest
    assert sha(native/'route.db')==record['routed_db_sha256']
    assessments=[]
    for phase in ('route','final'):
        verdict=assess(read_report(native/(phase+'.timing')),read_report(native/(phase+'.check')))
        assert verdict['timing_passed'] and verdict['gate_accepted'],verdict
        assert all(x['reported_min_ns'] is not None and x['reported_min_ns']>=0 for x in verdict['minima'].values())
        assert verdict==record['assessments'][len(assessments)]
        assessments.append(verdict)
    results=read(sim/'results.json');assert results['complete'] and len(results['results'])==1
    entry=results['results'][0]
    assert entry['status']=='PASS' and entry['checks']==98 and entry['data_comparisons']==2880
    assert entry['top']=='tb_v3_adapter_traffic_trace' and not entry['source_overrides']
    case=sim/entry['top'];text=(case/'sim.log').read_text(encoding='utf-8',errors='replace')
    assert '$finish called' in text and re.search(r'\[TB\] tb_v3_adapter_traffic_trace done, errors=0 comparisons=2880',text)
    assert not re.search(r'\[FAIL\]|\[SKIP\]|^\s*(?:ERROR:|Fatal:|FATAL)',text,re.M)
    for label in ('odd path detects exactly the injected error','even path detects exactly the injected error'):
        assert '[PASS] '+label in text
    for name,digest in read(case/'sources.sha256.json').items():
        assert sha(ROOT/name)==digest,name;deps[name]=digest
    proof_root=ROOT/'evidence/v3/adapter_traffic_26101725/model'
    proof_pairs=[(case/'sim.log',proof_root/'positive/sim.log'),
                 (case/'sources.sha256.json',proof_root/'positive/sources.sha256.json'),
                 (sim/'results.json',proof_root/'positive/runner.results.json')]
    negative_files=[]
    for label,count in (('legacy_two_beats',255),('unmasked_padding',26),('no_reverse_rows',2328),('no_long_pauses',1)):
        negative=controls/label;meta=read(negative/'case.json');target=meta['target']
        allowed={'legacy_two_beats':'sdram_app_adapter.v','unmasked_padding':'sdram_app_adapter.v',
                 'no_reverse_rows':'sv_v3_adapter_traffic_trace.v','no_long_pauses':'sv_v3_adapter_traffic_trace.v'}
        assert target=='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/'+allowed[label]
        assert meta['mutation']==label and meta['detected'] and meta['normal_completion']
        assert sha(ROOT/target)==meta['original_sha256'] and sha(negative/'mutant.v')==meta['mutated_sha256']
        expected=(ROOT/target).read_text(encoding='utf-8')
        for patch in meta['patch']:
            assert expected.count(patch['before'])==1
            expected=expected.replace(patch['before'],patch['after'])
        assert expected==(negative/'mutant.v').read_text(encoding='utf-8')
        neg_folder=negative/'simulation/tb_v3_adapter_traffic_trace'
        text=(neg_folder/'sim.log').read_text(encoding='utf-8',errors='replace')
        assert '$finish called' in text and f'done, errors={count} comparisons=2880' in text
        assert len(re.findall(r'(?m)^\[FAIL\]',text))==count
        assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)|watchdog',text)
        markers={'unmasked_padding':'[FAIL] all poisoned neighbour words preserved',
                 'no_reverse_rows':'[FAIL] independent reverse-row input order',
                 'no_long_pauses':'[FAIL] long pauses exercised in both adapter directions'}
        if label in markers:assert markers[label] in text
        for name,digest in read(neg_folder/'sources.sha256.json').items():
            assert sha(negative/'mutant.v' if name==target else ROOT/name)==digest,name
        proof_pairs += [(neg_folder/'sim.log',proof_root/label/'sim.log'),
                        (neg_folder/'sources.sha256.json',proof_root/label/'sources.sha256.json'),
                        (negative/'simulation/results.json',proof_root/label/'runner.results.json'),
                        (negative/'case.json',proof_root/label/'case.json'),
                        (negative/'mutant.v',proof_root/label/'mutant.v')]
        negative_files += [negative/'case.json',negative/'mutant.v',negative/'simulation/results.json',
                           neg_folder/'sim.log',neg_folder/'sources.sha256.json']
    for original,committed in proof_pairs:
        assert sha(original)==sha(committed)
        deps[committed.relative_to(ROOT).as_posix()]=sha(committed)
    negative_hashes={str(path):sha(path) for path in negative_files}
    for name in (project+'native.sources.json','safevision/tools/run_adapter_traffic_trace.py',
      'safevision/tools/finalize_adapter_traffic_trace.py','safevision/tools/run_v3_board.py',
      'safevision/tools/check_board_timing.py','safevision/tools/generate_adapter_traffic_vectors.py'):
        deps[name]=sha(ROOT/name)
    binding=source_commit_binding(ROOT,ROOT,a.source_ref,deps)
    assert binding['verified'],binding
    out=ROOT/'artifacts/diagnostics/adapter_traffic_26101725'
    assert not out.exists(),'Never replace an existing diagnostic package'
    out.mkdir(parents=True)
    names=['route.timing','route.check','route.status','route.exceptions','route.area','gate.area',
      'route.db','route.tcl','route.console.log','route.derived.sdc','gate.netlist.v',
      'final.timing','final.check','final.status','final.exceptions','final.clocks',
      'final.tcl','final.console.log','native.acceptance.json','sources.sha256.json']
    reports={n:sha(native/n) for n in names}
    (out/'native').mkdir();(out/'simulation').mkdir()
    (out/'negative_controls').mkdir()
    for number,path in enumerate(negative_files):
        shutil.copyfile(path,out/'negative_controls'/(str(number)+'_'+path.name))
    for name in names:shutil.copyfile(native/name,out/'native'/name)
    for name in ('sim.log','sim.console.log','sources.sha256.json','compile.log','elab.log'):
        shutil.copyfile(case/name,out/'simulation'/name)
    shutil.copyfile(sim/'results.json',out/'simulation/results.json')
    for name in deps:
        dst=out/'source'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,dst)
    shutil.copyfile(ROOT/'docs/v3/adapter_traffic_26101725.md',out/'README.md')
    exe=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
    executable_hash=sha(exe)
    bit=out/'SafeVision_ADAPTER_TRAFFIC_26101725.bit';pending=out/(bit.name+'.pending')
    tcl=out/'bitgen.tcl'
    tcl.write_bytes(('if {[catch {\nimport_db {'+(out/'native/route.db').as_posix()+'}\nbitgen -bit {'+
      pending.as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "ADAPTER PATH BITGEN COMPLETE"\nexit 0\n').encode())
    _,log=invoke(exe,tcl,out/'bitgen.console.log',os.environ.copy())
    assert 'ADAPTER PATH BITGEN COMPLETE' in log and pending.stat().st_size>0
    assert sha(exe)==executable_hash
    assert all(sha(native/n)==digest and sha(out/'native'/n)==digest for n,digest in reports.items())
    assert all(sha(ROOT/n)==digest and sha(out/'source'/n)==digest for n,digest in deps.items())
    assert all(sha(ROOT/n)==digest for n,digest in read(case/'sources.sha256.json').items())
    assert all(sha(Path(path))==digest for path,digest in negative_hashes.items())
    for number,path in enumerate(negative_files):
        assert sha(out/'negative_controls'/(str(number)+'_'+path.name))==negative_hashes[str(path)]
    pending.replace(bit)
    index=dict(id='26101725',diagnostic_only=True,production_application=False,hardware_verified=False,
      uart_header='SVADP26101725',profile='MEM50MHz_SDRAM_PLUS8NS_REVERSE_ROWS_MIXED_WRITE_LONG_PAUSE_READ_BACKPRESSURE',
      source_commit_binding=binding,source_sha256=deps,native_reports_sha256=reports,
      all_check_types=assessments[-1],simulation_checks=98,simulation_comparisons=2880,
      negative_controls=['odd_path_single_bit','even_path_single_bit','legacy_two_beats','unmasked_padding','no_reverse_rows','no_long_pauses'],semantic_control_errors={'legacy_two_beats':255,'unmasked_padding':26,'no_reverse_rows':2328,'no_long_pauses':1},
      td_version='6.2.168116',td_executable=str(exe),td_executable_sha256=executable_hash,
      expected_rounds=12,expected_final_pattern=5,expected_total_words=46272,
      expected_target_writes_each=3840,expected_reads_captured_each=3856,guard_words_each=16,report_bytes=231,
      bitstream=bit.name,bytes=bit.stat().st_size,sha256=sha(bit),github_upload_performed=False)
    save(out/'probe.index.json',index)
    payload={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()}
    save(out/'payload.sha256.json',payload)
    print(json.dumps({k:index[k] for k in ('id','bitstream','bytes','sha256','source_commit_binding','hardware_verified')},indent=2))
    return 0
if __name__=='__main__':sys.exit(main())
