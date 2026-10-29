


from pathlib import Path
import hashlib,json,re

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
STRICT_RUNNER='safevision/tools/run_v3_sim_flexible.py'
def strict_inputs(root,folder,manifest,top,before=None):

    root=Path(root).resolve();folder=Path(folder).resolve()
    assert manifest.get('strict_generated_inputs')==1,'strict manifest flag absent'
    assert manifest.get('native_runner')==STRICT_RUNNER,'strict FLEX runner not selected'
    before=before if before is not None else read(folder/'sources.sha256.json')
    assert STRICT_RUNNER in before,'strict FLEX runner missing from actual original capture'
    assert before[STRICT_RUNNER]==hashlib.sha256((root/STRICT_RUNNER).read_bytes()).hexdigest(),'strict runner changed'
    for key in ('generator_dependencies','generated_assets'):
        assert isinstance(manifest.get(key),list),'strict manifest requires explicit '+key
        assert len(manifest[key])==len(set(manifest[key])),'duplicate strict '+key
    generation_before=read(folder/'generation.before.sha256.json');generation_after=read(folder/'generation.after.sha256.json')
    assert generation_before==generation_after,'source or generator dependency changed during generation'
    nongenerated={name:digest for name,digest in before.items()if not name.startswith('generated:')}
    assert nongenerated==generation_before,'pre-generation fingerprint differs from compiled input capture'
    generator=manifest.get('generators',{}).get(top)
    manifest_inputs=[name for name in before if name.startswith('safevision/build/manifests/')and name.endswith('_sim.json')]
    assert len(manifest_inputs)==1,'one explicit strict manifest fingerprint required'
    assert read(root/manifest_inputs[0])==manifest,'captured manifest is not the selected strict manifest'
    required=list(manifest['generator_dependencies'])+[STRICT_RUNNER]+manifest_inputs
    if generator:required.append(generator)
    for name in required:
        assert name in before,'explicit generator dependency missing in original capture: '+name
        path=(root/name).resolve();assert path.is_relative_to(root),'generator dependency escaped root'
        assert path.is_file()and hashlib.sha256(path.read_bytes()).hexdigest()==before[name],'generator dependency changed: '+name
    copied={Path(name).name:name for name in manifest.get('assets',[])}
    assert len(copied)==len(manifest.get('assets',[])),'copied asset basename collision'
    generated=list(manifest['generated_assets'])+list(copied)
    assert len(generated)==len(set(generated)),'copied/generated runtime asset collision'
    assert {name for name in before if name.startswith('generated:')}=={'generated:'+name for name in generated},'declared runtime assets differ from captured original files'
    for name in generated:
        assert isinstance(name,str)and name and not Path(name).is_absolute(),'invalid generated relative asset path'
        path=(folder/name).resolve();assert path.is_relative_to(folder),'runtime asset escaped evidence folder: '+name
        assert path.is_file()and hashlib.sha256(path.read_bytes()).hexdigest()==before['generated:'+name],'runtime asset changed or missing: '+name
        if name in copied:assert before['generated:'+name]==before[copied[name]],'runtime static copy differs from captured source asset'
    after=read(folder/'sources.after.sha256.json');assert after==before,'source/runtime asset changed during native execution'
    return dict(strict_generated_inputs_verified=True,native_runner=STRICT_RUNNER,generator_dependencies=len(manifest['generator_dependencies']),runtime_assets=len(generated),generation_inputs=len(generation_before),generation_before_sha256=hashlib.sha256((folder/'generation.before.sha256.json').read_bytes()).hexdigest(),generation_after_sha256=hashlib.sha256((folder/'generation.after.sha256.json').read_bytes()).hexdigest())
def check(root,folder,metadata,negative=None):
    root=Path(root).resolve();folder=Path(folder).resolve();before=read(folder/'sources.sha256.json')
    hdl=[n for n in before if not n.startswith('generated:') and n.endswith(('.v','.sv'))]
    logs=metadata.get('compiler_logs',['compile.log'])
    log='\n'.join((folder/n).read_text(encoding='utf-8',errors='replace')for n in logs if(folder/n).is_file())
    paths=re.findall(r'Analyzing (?:SystemVerilog|Verilog) file "([^"]+)"',log)
    if not paths and (folder/'sources.prj').is_file():
        paths=re.findall(r'"([^"]+\.(?:v|sv))"',(folder/'sources.prj').read_text(encoding='utf-8'))
    assert paths,'missing actual compiler HDL graph: '+str(folder)
    observed=[]
    mutant=[n for n in hdl if negative and before[n]==negative['mutated_sha256']]
    for name in paths:
        normalized=name.replace('\\','/');marker='/safevision/'
        if marker in normalized:
            logical='safevision/'+normalized.split(marker,1)[1]
        elif negative and len(mutant)==1:
            logical=mutant[0]
        else:
            hits=[n for n in hdl if Path(n).name==Path(normalized).name]
            assert len(hits)==1,('ambiguous analyzed HDL',name,hits);logical=hits[0]
        assert logical in before,('analyzed HDL has no captured fingerprint',logical)
        observed.append(logical)
    assert len(observed)==len(set(observed)),'duplicate analyzed HDL'
    suite=metadata['suite'];top=metadata['top'];manifest=root/'safevision/build/manifests'/(suite+'_sim.json')
    if manifest.is_file():
        m=read(manifest);assert top in m['tops'];tests=m.get('test_sources',{}).get(top,['safevision/verification/unit/'+top+'.sv'])
        if isinstance(tests,str):tests=[tests]
        expected=list(dict.fromkeys(m['sources']+tests))
        assert observed==expected,('current selected manifest differs from analyzed HDL',top,sorted(set(expected)-set(observed)),sorted(set(observed)-set(expected)))
        assert all(n in before for n in m.get('assets',[])),'current sim asset missing in original input capture'
        generator=m.get('generators',{}).get(top)
        if generator:assert generator in before,'current generator missing in original input capture'
        digest=hashlib.sha256(manifest.read_bytes()).hexdigest()
        if metadata.get('producer_manifest_sha256'):assert metadata['producer_manifest_sha256']==digest,'producer manifest changed'
        strict=strict_inputs(root,folder,m,top,before)if m.get('strict_generated_inputs')==1 else {}
        return dict(accepted=True,top=top,suite=suite,ordered_analyzed_HDL=len(observed),manifest=manifest.relative_to(root).as_posix(),current_manifest_sha256=digest,binding='actual_compiler_and_current_manifest',**strict)
    assert metadata.get('legacy'),('modern suite lacks explicit current manifest',suite)


    assert set(observed)<=set(hdl),'legacy analyzed dependency missing in captured inputs'
    assert any(Path(n).stem==top for n in observed),'legacy selected bench was not analyzed'
    return dict(accepted=True,top=top,suite=suite,ordered_analyzed_HDL=len(observed),additional_hashed_inputs=len(set(hdl)-set(observed)),binding='historical_actual_compiler_graph_covered_by_current_input_hashes')
