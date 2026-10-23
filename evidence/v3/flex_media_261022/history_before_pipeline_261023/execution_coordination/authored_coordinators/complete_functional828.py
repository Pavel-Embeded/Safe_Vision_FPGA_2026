"""Set complete only after every actual raw capture and mandatory aux gate audits."""
from pathlib import Path
import sys,json,hashlib,shutil
B=Path('D:/Codex/svflex537');R=B/'candidate803';read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
cohort=read(B/'qualification811/complete.json');assert cohort['complete']and len(cohort['results'])==524 and all(r['accepted']for r in cohort['results'])
exitproof=read(B/'qualification811/coordinator_resume819/actual_native_exits.json');assert exitproof['complete']and len(exitproof['records'])==4 and all(r['actual_process_exit']==0 for r in exitproof['records'])
I=R/'evidence/v3/four_features_261020/acceptance.json';index=read(I);assert not index['complete'];original=I.read_bytes()
H=R/'evidence/v3/flex_media_261022/history_before_pipeline_261023/execution_coordination';assert not H.exists();H.mkdir(parents=True)
records={}
for folder in ['coordinator_resume819','coordinator_shared_storage823']:
 for p in(B/'qualification811'/folder).iterdir():
  if p.is_file():q=H/folder/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q);assert sha(q)==sha(p);records[q.relative_to(H).as_posix()]=sha(q)
for n in ['requalify_features811.py','resume_qualification819.py','adopt_shared_storage823.py','record_native_exit824.py']:
 p=Path('work')/n;q=H/'authored_coordinators'/n;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q);records[q.relative_to(H).as_posix()]=sha(q)
diag=B/'qualification830';rep=read(diag/'replacement.receipt.json');assert rep['accepted']and len(rep['replacements'])==8
shutil.copytree(diag/'before_install',H/'diagnostic_fixture_before')
for n in ['fixture.patch.json','complete.json','replacement.receipt.json']:shutil.copyfile(diag/n,H/('diagnostic_'+n))
for row in rep['replacements']:
 old=row['failed_original'];assert not old['accepted'];src=Path(old['producer_folder']).resolve();assert src.is_relative_to((B/'qualification811').resolve())
 dst=H/'original_failed_diagnostic_runs'/old['kind']/old['name'];dst.mkdir(parents=True)
 for p in src.iterdir():
  if p.is_file():shutil.copyfile(p,dst/p.name)
 for p in [src.parent.parent/'runner.console.log',src.parent.parent/'exception.txt']:
  if p.is_file():shutil.copyfile(p,dst/p.name)
counter=B/'qualification832';assert read(counter/'complete.json')['complete'];shutil.copyfile(counter/'complete.json',H/'coherent_counter_fault.complete.json');shutil.copyfile(counter/'runner.console.log',H/'coherent_counter_fault.runner.console.log')
for n in ['requalify_diag830.py','merge_diag831.py','prepare_merge833.py','merge_final833.py','requalify_counter832.py']:
 p=Path('work')/n;shutil.copyfile(p,H/'authored_coordinators'/n)
for p in H.rglob('*'):
 if p.is_file():records[p.relative_to(H).as_posix()]=sha(p)
(H/'preserved.inputs.json').write_text(json.dumps(records,indent=2)+'\n')
sys.path.insert(0,str(R/'safevision/tools'));from audit_v3_four_features import audit
manifest='evidence/v3/four_features_261020/acceptance.json';preflight=audit(R,manifest,R,inspect_incomplete=True)
assert not preflight['accepted']and not preflight['missing_positive']and preflight['positive_unique_tops']==303 and len(preflight['negative'])==221 and preflight['physical_inputs']==205
for n in ['flexible_media_auxiliary','compact_ingress_auxiliary','wav_pipeline_auxiliary','lba_control_clock_auxiliary','pipeline_auxiliary']:assert preflight[n]['accepted']
(B/'functional828.preflight.json').write_text(json.dumps(preflight,indent=2)+'\n')
try:
 index['complete']=True;I.write_text(json.dumps(index,indent=2)+'\n');final=audit(R,manifest,R);assert final['accepted'];(B/'functional818.audit.json').write_text(json.dumps(final,indent=2)+'\n')
except BaseException:I.write_bytes(original);raise
print('Full current803 functional gate PASS:303 positives221 normally detecting mutants; all mandatory aux gates PASS.',flush=True)
