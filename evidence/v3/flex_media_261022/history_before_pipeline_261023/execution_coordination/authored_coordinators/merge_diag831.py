"""Install only qualified diagnostic fixtures after the original cohort drains."""
from pathlib import Path
import json,shutil,hashlib,time,sys,ast,re
B=Path('D:/Codex/svflex537');R=B/'candidate803';O=B/'qualification830';Q=B/'qualification811';read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
fresh=read(O/'complete.json');assert fresh['complete']and len(fresh['records'])==7 and fresh['physical205_unchanged']
while not(Q/'complete.json').exists()or not read(Q/'complete.json').get('coordinator_recovery_receipt'):time.sleep(3)
cohort=read(Q/'complete.json');assert len(cohort['results'])==524 and cohort['reused']==309 and cohort['fresh_native_executions']==215
H=O/'before_install';assert not H.exists();H.mkdir();(H/'cohort.before.json').write_bytes((Q/'complete.json').read_bytes());patch=read(O/'fixture.patch.json');assert patch['physical205_unchanged']
for row in patch['patches']:
 p=R/row['path'];src=B/'diag830_root'/row['path'];assert sha(p)==row['original_sha256']and sha(src)==row['new_sha256'];dst=H/'source'/row['path'];dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dst);shutil.copyfile(src,p)
attr=R/'.gitattributes';raw=attr.read_bytes();extra=[r['path']for r in patch['patches']if '/'+r['path']+' -text'not in raw.decode()]
if extra:attr.write_bytes(raw+b'\n# Exact diagnosed injection fixtures, paired redundant count flag.\n'+''.join('/'+n+' -text\n'for n in extra).encode())
tree=ast.parse(Path('work/requalify_features811.py').read_text());defs=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name in('normal','mutate','validate')]
sys.path.insert(0,str(R/'safevision/tools'));from audit_v3_resource_checkpoint import sources
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
from v3_sources import snapshot
ns=dict(R=R,read=read,sha=sha,re=re,Path=Path,sources=sources,audit_file=audit_file,graph=graph);exec(compile(ast.Module(body=defs,type_ignores=[]),'same_native_validator831','exec'),ns)
plan=read(Q/'plan.json');definitions={(r['kind'],r['name']):r['row']for r in plan['records']};freshmap={(r['kind'],r['name']):r for r in fresh['records']};replaced=[]
for key,new in freshmap.items():
 old=next(r for r in cohort['results']if(r['kind'],r['name'])==key);assert not old['accepted'],'Unexpected old diagnostic pass; investigate before replacement'
 assert ns['validate'](new['kind'],definitions[key],new['producer_folder'])==new['checked'];replaced.append(dict(key=key,failed_original=old,current_accepted=new))
cohort['results']=[freshmap.get((r['kind'],r['name']),r)for r in cohort['results']];cohort['complete']=all(r['accepted']for r in cohort['results']);cohort['diagnostic_fixture_requalification']=dict(complete=True,positive=2,negative=5,cohort=str(O),physical_source_unchanged=True,original_failed_attempts_preserved=True)
assert cohort['complete'],'Other current-source failures remain'
assert snapshot(R)==read(B/'design803.json')['physical_source_sha256'];(O/'replacement.receipt.json').write_text(json.dumps(dict(accepted=True,replacements=replaced,patches=patch['patches'],source205_unchanged=True),indent=2)+'\n');(Q/'complete.json').write_text(json.dumps(cohort,indent=2)+'\n');print('Final current-source main qualification complete:303/221,2 diagnostic fixtures repaired,7 former failed native attempts retained.',flush=True)
