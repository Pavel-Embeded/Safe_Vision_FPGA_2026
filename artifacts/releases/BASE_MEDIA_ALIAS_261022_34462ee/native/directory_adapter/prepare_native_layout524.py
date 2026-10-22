"""Adapt a flat original TD run to the release tool's directory contract.

Native databases, reports and the original build record remain untouched.
The identity receipt explicitly records that this snapshot was made afterward.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,datetime
S=Path('D:/Codex/svmultires510/source');N=S.parent/'native/base'
O=Path('D:/Codex/svmedia_native524');F=O/'base/source';T=O/'base/td'
O.mkdir();F.mkdir(parents=True);T.mkdir()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
save=lambda p,j:p.write_text(json.dumps(j,indent=2)+'\n',encoding='utf-8')
record=read(N/'build.manifest.json');original_manifest=sha(N/'build.manifest.json')
sys.path.insert(0,str(S/'safevision/tools'))
from v3_sources import snapshot
from finalize_v3_board_release import native_acceptance
current=snapshot(S);assert current==record['sources'] and len(current)==198
for name,digest in current.items():
 p=F/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(S/name,p)
 assert sha(p)==digest
assert snapshot(F)==current
command="New-Item -ItemType Junction -Path '"+str(T/'base')+"' -Target '"+str(N)+"' | Out-Null"
subprocess.run(['powershell','-NoProfile','-Command',command],check=True)
assert (T/'base').resolve()==N.resolve()
identity=dict(mode='base',source_commit=record['source_commit'],sources=current,
 snapshot_created_at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
 snapshot_created_after_native_run=True,original_native_folder=str(N),
 original_build_manifest_sha256=original_manifest,
 provenance='Exact 198 current bytes verified against the unchanged original native build record; directory adapter only, not a new build.')
save(O/'base/source.identity.json',identity)
n=native_acceptance(S,O,'base',current)
assert n['gate']['gate_accepted'] and n['gate']['timing_passed']
assert sha(N/'build.manifest.json')==original_manifest
save(O/'layout.receipt.json',dict(accepted=True,source_inputs=198,original_reports_unchanged=True,
 original_native_folder=str(N),original_manifest_sha256=original_manifest,
 original_record_source_commit=record['source_commit'],strict_native_acceptance=n['gate']))
print('ORIGINAL NATIVE RUN / 198-BYTE SNAPSHOT / STRICT GATE VERIFIED',flush=True)
