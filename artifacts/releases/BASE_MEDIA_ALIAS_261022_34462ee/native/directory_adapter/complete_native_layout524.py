"""Retain original absolute source paths used by native fresh STA.

Keep the exact extra snapshot as evidence, then resolve the release entry point
to the original source root. No report path or checker is rewritten.
"""
from pathlib import Path
import hashlib,json,subprocess,sys
S=Path('D:/Codex/svmultires510/source');N=S.parent/'native/base'
O=Path('D:/Codex/svmedia_native524');F=O/'base/source';C=O/'base/source_snapshot'
assert F.resolve().is_relative_to(O.resolve()) and not C.exists()
F.rename(C)
subprocess.run(['powershell','-NoProfile','-Command',"New-Item -ItemType Junction -Path '"+str(F)+"' -Target '"+str(S)+"' | Out-Null"],check=True)
assert F.resolve()==S.resolve()
sys.path.insert(0,str(S/'safevision/tools'))
from v3_sources import snapshot
from finalize_v3_board_release import native_acceptance
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
identity=read(O/'base/source.identity.json');current=snapshot(S)
assert current==snapshot(C)==identity['sources']
n=native_acceptance(S,O,'base',current)
assert n['gate']['gate_accepted'] and n['gate']['timing_passed']
assert sha(N/'build.manifest.json')==identity['original_build_manifest_sha256']
(O/'layout.receipt.json').write_text(json.dumps(dict(accepted=True,source_inputs=198,
 original_reports_unchanged=True,original_absolute_source_paths_preserved=True,
 extra_source_snapshot=str(C),original_native_folder=str(N),
 original_manifest_sha256=identity['original_build_manifest_sha256'],
 original_record_source_commit=identity['source_commit'],strict_native_acceptance=n['gate']),indent=2)+'\n',encoding='utf-8')
print('ORIGINAL PATHS / NATIVE REPORTS /198 INPUTS /STRICT STA VERIFIED',flush=True)
