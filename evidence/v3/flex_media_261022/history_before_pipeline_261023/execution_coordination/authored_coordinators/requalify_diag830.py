"""Keep diagnostic fault injection consistent with the live unary word-count invariant.

No RTL/SDC changes; original failing fixtures and logs remain intact. Run both
positive diagnostic interfaces and all five existing semantic negative controls.
"""
from pathlib import Path
import json,hashlib,shutil,subprocess,sys,re,ast,concurrent.futures
B=Path('D:/Codex/svflex537');S=B/'candidate803';R=B/'diag830_root';O=B/'qualification830';R.mkdir(exist_ok=True);O.mkdir(exist_ok=True);assert {p.name for p in O.iterdir()}<= {'fixture.patch.json'}
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
sys.path.insert(0,str(S/'safevision/tools'));from v3_sources import snapshot
physical=snapshot(S);assert physical==read(B/'design803.json')['physical_source_sha256'];names=set(physical)
for suite in ['diag_board','diag_alias156']:
 n=f'safevision/build/manifests/{suite}_sim.json';m=read(S/n);names.add(n);names.update(m['sources']);names.update(m.get('assets',[]));names.update('safevision/verification/unit/'+t+'.sv'for t in m['tops'])
names.update(p.relative_to(S).as_posix()for p in(S/'safevision/rtl/include').glob('*.vh'));names.update(p.relative_to(S).as_posix()for p in(S/'safevision/tools').glob('*.py'))
for n in names:p=R/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(S/n,p)
patches=[]
for top in ['tb_v3_diag_board','tb_v3_diag_alias156']:
 n='safevision/verification/unit/'+top+'.sv';p=R/n;v=p.read_text();anchor="force dut.guard_words=32'h00025800;";assert v.count(anchor)==1
 replacement="""// This diagnostic-only injection forces the source count through its
  // continuous output alias. Keep its redundant zero flag consistent; the
  // live memory invariant remains enabled and all diagnostic checks remain.
  force dut.row_guard.source_first=1'b0;
  """+anchor
 p.write_bytes(v.replace(anchor,replacement).encode());patches.append(dict(path=n,before=anchor,after=replacement,original_sha256=sha(S/n),new_sha256=sha(p)))
(O/'fixture.patch.json').write_text(json.dumps(dict(physical205_unchanged=snapshot(R)==physical,patches=patches,reason='Diagnostic force of source_words aliases internal source_count, so its redundant zero flag must be forced consistently; no RTL assertion removed'),indent=2)+'\n')
tree=ast.parse(Path('work/requalify_features811.py').read_text());defs=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name in('normal','mutate','validate')]
from audit_v3_resource_checkpoint import sources
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
ns=dict(R=R,read=read,sha=sha,re=re,Path=Path,sources=sources,audit_file=audit_file,graph=graph);exec(compile(ast.Module(body=defs,type_ignores=[]),'unchanged_source_checker830','exec'),ns)
matrix=read(S/'safevision/build/qualification/four_features_261020.json');specs=[(kind,row)for kind in ['positive','negative']for row in matrix[kind]if row['suite']in ['diag_board','diag_alias156']];assert len(specs)==7
index=read(S/'evidence/v3/four_features_261020/acceptance.json');wanted_neg={r['mutation']for kind,r in specs if kind=='negative'};old_neg={r['mutation']:read(S/r['evidence']/'case.json')for r in index['negative_controls']if r['mutation']in wanted_neg}
def run(spec):
 kind,row=spec;name=row['top']if kind=='positive'else row['mutation'];out=O/kind/name;folder=out/'sim'/row['top'];out.mkdir(parents=True);cmd=[sys.executable,'-X','utf8','-B',str(R/'safevision/tools/run_v3_sim.py'),'--suite',row['suite'],'--top',row['top'],'--run-dir',str(out/'sim')]
 if kind=='negative':
  v=(R/row['target']).read_text()
  for patch in row['patch']:assert v.count(patch['before'])==patch.get('occurrences',1);v=v.replace(patch['before'],patch['after'])
  mutant=out/'mutant.v';mutant.write_bytes(v.encode());cmd+=['--override-source',row['target']+'='+str(mutant)]
 with(out/'runner.console.log').open('wb')as f:q=subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=180)
 wrapper=read(out/'sim/results.json');meta=wrapper['results'][0];assert meta['top']==row['top']
 if kind=='positive':
  assert q.returncode==0 and wrapper['complete']and meta['status']=='PASS'and not meta['source_overrides'];meta.update(suite=row['suite'],legacy=False,accepted_native_runner=True,producer_process_exit=0,original_producer=str(folder));(folder/'result.json').write_text(json.dumps(meta,indent=2)+'\n')
 else:
  assert q.returncode==1 and not wrapper['complete']and meta['status']=='FAIL'and meta['source_overrides']==[row['target']];shutil.copyfile(mutant,folder/'mutant.v');errors=ns['normal'](folder,row['top'],True);case=dict(row,original_sha256=sha(R/row['target']),mutated_sha256=sha(mutant),mutant_file='mutant.v',process_exit=1,return_code=1,normal_completion=True,error_counts=errors,detected=True,original_producer=str(folder))
  if old_neg[name].get('required_marker'):case['required_marker']=old_neg[name]['required_marker']
  (folder/'case.json').write_text(json.dumps(case,indent=2)+'\n')
 checked=ns['validate'](kind,row,folder);record=dict(kind=kind,name=name,accepted=True,action='fresh_native_execution',producer_folder=str(folder),checked=checked,elapsed_s=meta['elapsed_s'],diagnostic_fixture_consistency_repair=True)
 print(json.dumps(dict(name=name,accepted=True,errors=checked['error_counts'])),flush=True);return record
with concurrent.futures.ThreadPoolExecutor(max_workers=4)as pool:records=list(pool.map(run,specs))
assert len(records)==7 and snapshot(S)==snapshot(R)==physical
(O/'complete.json').write_text(json.dumps(dict(complete=True,records=records,source_commit=read(B/'design803.json')['commit'],physical205_unchanged=True,original_failing_records_preserved=True),indent=2)+'\n');print('Diagnostic fixture repair qualified:2 positive5 native negative normal completions; no RTL changes.',flush=True)
