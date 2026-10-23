"""Exercise a coherently shortened counter through its public oracle, keeping RTL assertions."""
from pathlib import Path
import json,shutil,hashlib,sys,subprocess,re,ast
B=Path('D:/Codex/svflex537');S=B/'candidate803';R=B/'counter832_root';O=B/'qualification832';R.mkdir(exist_ok=False);O.mkdir(exist_ok=False)
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
sys.path.insert(0,str(S/'safevision/tools'));from v3_sources import snapshot
physical=snapshot(S);names=set(physical);n='safevision/build/manifests/v3_sim.json';m=read(S/n);names.add(n);names.update(m['sources']);names.update(m.get('assets',[]));names.update('safevision/verification/unit/'+t+'.sv'for t in m['tops']);names.update(p.relative_to(S).as_posix()for p in(S/'safevision/tools').glob('*.py'));names.update(p.relative_to(S).as_posix()for p in(S/'safevision/rtl/include').glob('*.vh'))
for n in names:p=R/n;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(S/n,p)
matrix=read(S/'safevision/build/qualification/four_features_261020.json');old=next(r for r in matrix['negative']if r['mutation']=='frame_counter_one_bit_short');row=json.loads(json.dumps(old));row['patch'].append(dict(before="source_count<=source_words+1'b1;source_first<=0;",after="source_count<=source_words+1'b1;source_first<=(source_words[SOURCE_W-1:0]=={SOURCE_W{1'b1}});"))
v=(R/row['target']).read_text()
for patch in row['patch']:assert v.count(patch['before'])==1;v=v.replace(patch['before'],patch['after'])
assert 'if(source_first !== (source_words==0))$fatal'in v,'Production invariant must remain in the mutant'
mutant=O/'mutant.v';mutant.write_bytes(v.encode());out=O/'run';cmd=[sys.executable,'-X','utf8','-B',str(R/'safevision/tools/run_v3_sim.py'),'--suite',row['suite'],'--top',row['top'],'--run-dir',str(out),'--override-source',row['target']+'='+str(mutant)]
with(O/'runner.console.log').open('wb')as f:q=subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=180)
wrapper=read(out/'results.json');meta=wrapper['results'][0];folder=out/row['top'];assert q.returncode==1 and not wrapper['complete']and meta['status']=='FAIL'and meta['source_overrides']==[row['target']];shutil.copyfile(mutant,folder/'mutant.v')
text=(folder/'sim.log').read_text();errors=[int(x)for x in re.findall(r'errors\s*=\s*(\d+)',text)];assert errors and any(errors)and '$finish called'in text and 'PASS '+row['top']in text and '[FAIL]'in text and not re.search(r'(?im)^\s*(Fatal:|ERROR:|FATAL|SKIP)',text)
case=dict(row,original_sha256=sha(R/row['target']),mutated_sha256=sha(mutant),mutant_file='mutant.v',process_exit=1,return_code=1,normal_completion=True,detected=True,error_counts=errors,original_producer=str(folder));(folder/'case.json').write_text(json.dumps(case,indent=2)+'\n')
tree=ast.parse(Path('work/requalify_features811.py').read_text());defs=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name in('normal','mutate','validate')]
from audit_v3_resource_checkpoint import sources
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
ns=dict(R=R,Path=Path,read=read,sha=sha,re=re,sources=sources,audit_file=audit_file,graph=graph);exec(compile(ast.Module(body=defs,type_ignores=[]),'same_validator832','exec'),ns);checked=ns['validate']('negative',row,folder)
record=dict(kind='negative',name=row['mutation'],accepted=True,action='fresh_native_execution',producer_folder=str(folder),checked=checked,elapsed_s=meta['elapsed_s'],coherent_redundant_counter_fault_model=True)
assert snapshot(R)==snapshot(S)==physical
(O/'complete.json').write_text(json.dumps(dict(complete=True,original_definition=old,revised_definition=row,record=record,physical205_unchanged=True,production_assertions_unchanged=True,independent_public_count_oracle_detected=True),indent=2)+'\n');print('Coherent counter-width fault normally finished and detected by unchanged public oracle: '+str(errors),flush=True)
