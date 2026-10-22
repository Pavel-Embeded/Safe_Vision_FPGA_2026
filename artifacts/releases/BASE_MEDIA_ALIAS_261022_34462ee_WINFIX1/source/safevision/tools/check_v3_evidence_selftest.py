"""Prove scratch snapshots and incomplete suites cannot become production PASS."""
import argparse,hashlib,json
from pathlib import Path
from collect_v3_evidence import inspect_result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--run-dir',type=Path,required=True);a=parser.parse_args()
    out=a.run_dir.resolve();out.mkdir(parents=True,exist_ok=False)
    root=out/'production';root.mkdir();source=root/'module.v';source.write_text('module original;endmodule\n',encoding='ascii')
    scratch=out/'scratch.v';scratch.write_bytes(source.read_bytes())
    digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    def case(name,sources,expected,complete=True,status='PASS'):
        d=out/name;(d/'tb').mkdir(parents=True)
        result={'complete':complete,'results':[{'top':'tb','status':status}]}
        (d/'results.json').write_text(json.dumps(result),encoding='utf-8')
        (d/'tb/sources.sha256.json').write_text(json.dumps(sources),encoding='utf-8')
        (d/'tb/sim.log').write_text('[PASS] checked\nPASS tb errors=0\n$finish called\n',encoding='utf-8')
        got=inspect_result(d/'results.json',root)
        assert got['tests'][0]['top']=='tb',got
        assert got['tests'][0]['state']==expected,(name,got)
        assert got['all_current_pass']==(complete and expected=='CURRENT_PASS'),(name,got)
    case('relative_current',{'module.v':digest(source)},'CURRENT_PASS')
    case('absolute_current',{str(source):digest(source)},'CURRENT_PASS')
    case('scratch_same_bytes',{str(scratch):digest(scratch)},'EXTERNAL_SNAPSHOT_PASS')
    case('path_escape',{'../scratch.v':digest(scratch)},'EXTERNAL_SNAPSHOT_PASS')
    case('source_drift',{'module.v':'0'*64},'STALE_PASS')
    case('incomplete_suite',{'module.v':digest(source)},'CURRENT_PASS',False)
    case('failed_test',{'module.v':digest(source)},'FAIL_OR_INCOMPLETE',False,'FAIL')
    d=out/'empty_manifest';(d/'tb').mkdir(parents=True)
    (d/'results.json').write_text(json.dumps({'complete':True,'results':[{'top':'tb','status':'PASS'}]}),encoding='utf-8')
    (d/'tb/sources.sha256.json').write_text('{}',encoding='utf-8')
    try:inspect_result(d/'results.json',root)
    except ValueError:pass
    else:raise AssertionError('empty manifest accepted')
    def generated_case(name,mode,expected):
        d=out/name;folder=d/'tb';folder.mkdir(parents=True)
        manifest=root/'safevision/build/manifests/fixture_sim.json'
        manifest.parent.mkdir(parents=True,exist_ok=True)
        manifest.write_text(json.dumps({'generated_assets':['expected.mem']}),encoding='utf-8')
        asset=folder/'expected.mem';asset.write_text('12345678\n',encoding='ascii')
        (folder/'sim.log').write_text('[PASS] checked\nPASS tb errors=0\n$finish called\n',encoding='utf-8')
        src={'module.v':digest(source),
             'safevision/build/manifests/fixture_sim.json':digest(manifest),
             'generated:expected.mem':digest(asset)}
        if mode=='tamper_asset':asset.write_text('bad\n',encoding='ascii')
        if mode=='escape':src['generated:../escape.mem']=src.pop('generated:expected.mem')
        if mode=='undeclared':src['generated:unknown.mem']=src.pop('generated:expected.mem')
        if mode=='no_manifest':del src['safevision/build/manifests/fixture_sim.json']
        if mode=='manifest_drift':src['safevision/build/manifests/fixture_sim.json']='0'*64
        (d/'results.json').write_text(json.dumps({'suite':'fixture','complete':True,'results':[{'top':'tb','status':'PASS'}]}),encoding='utf-8')
        (folder/'sources.sha256.json').write_text(json.dumps(src),encoding='utf-8')
        if mode!='no_after':
            after=dict(src)
            if mode=='after_drift':after['generated:expected.mem']='0'*64
            (folder/'sources.after.sha256.json').write_text(json.dumps(after),encoding='utf-8')
        try:got=inspect_result(d/'results.json',root)
        except ValueError:
            assert expected=='REJECT',(name,expected)
        else:
            assert got['tests'][0]['top']=='tb',got
            assert expected!='REJECT' and got['tests'][0]['state']==expected,(name,got)
            assert got['all_current_pass']==(expected=='CURRENT_PASS'),(name,got)
    generated_case('generated_current','normal','CURRENT_PASS')
    generated_case('generated_tampered','tamper_asset','STALE_PASS')
    generated_case('generated_no_after','no_after','REJECT')
    generated_case('generated_after_drift','after_drift','STALE_PASS')
    generated_case('generated_escape','escape','REJECT')
    generated_case('generated_undeclared','undeclared','REJECT')
    generated_case('generated_no_manifest','no_manifest','REJECT')
    generated_case('generated_manifest_drift','manifest_drift','STALE_PASS')
    for label,badlog in [('prefixed_failure','[MODEL] [FAIL] corrupt\n'),('truncated','')]:
        d=out/label;(d/'tb').mkdir(parents=True)
        (d/'results.json').write_text(json.dumps({'complete':True,'results':[{'top':'tb','status':'PASS'}]}),encoding='utf-8')
        (d/'tb/sources.sha256.json').write_text(json.dumps({'module.v':digest(source)}),encoding='utf-8')
        (d/'tb/sim.log').write_text(badlog+('[PASS] data\nPASS tb errors=0\n$finish called\n' if badlog else '[PASS] unfinished\n'),encoding='utf-8')
        got=inspect_result(d/'results.json',root)
        assert got['tests'][0]['top']=='tb',got
        assert got['tests'][0]['state']=='RAW_LOG_REJECTED' and not got['all_current_pass'],got
    (out/'selftest.json').write_text(json.dumps({'checks':18,'errors':0,'release_ready':False}),encoding='utf-8')
    print('PASS evidence inventory scope/selftest checks=18 errors=0')
if __name__=='__main__':main()
