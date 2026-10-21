"""Verify the HDL actually analyzed matches the currently selected sim graph.

The runner already fingerprints its manifest and code. This independent check
additionally verifies the compiler's observed ordered inputs, rather than only
the intended input dictionary. Legacy suites retain their actual analyzed graph.
"""
from pathlib import Path
import hashlib,json,re

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
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
        return dict(accepted=True,top=top,suite=suite,ordered_analyzed_HDL=len(observed),manifest=manifest.relative_to(root).as_posix(),current_manifest_sha256=digest,binding='actual_compiler_and_current_manifest')
    assert metadata.get('legacy'),('modern suite lacks explicit current manifest',suite)
    # The historical A runner captured all five benches as one conservative
    # fingerprint set, then compiled one bench per native execution. Every
    # analyzed dependency must be captured; unused captured benches add no proof.
    assert set(observed)<=set(hdl),'legacy analyzed dependency missing in captured inputs'
    assert any(Path(n).stem==top for n in observed),'legacy selected bench was not analyzed'
    return dict(accepted=True,top=top,suite=suite,ordered_analyzed_HDL=len(observed),additional_hashed_inputs=len(set(hdl)-set(observed)),binding='historical_actual_compiler_graph_covered_by_current_input_hashes')
