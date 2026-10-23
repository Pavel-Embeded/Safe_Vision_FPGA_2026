"""Freshly execute every303/221 capture affected by the CRC, BMP and ALPHA timing changes.

Unchanged producers are rechecked, not relabelled as new executions. This
producer-only job never edits the source, acceptance index, matrix or Git.
"""
from pathlib import Path
import concurrent.futures,hashlib,json,re,subprocess,sys,threading,time,traceback,shutil
B=Path('D:/Codex/svflex537');R=B/'candidate803';O=B/'qualification811'
assert O.is_dir()and(O/'coordinator_resume819/receipt.json').is_file()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,j):
 t=p.with_suffix(p.suffix+'.writing');t.write_text(json.dumps(j,indent=2)+'\n',encoding='utf-8');t.replace(p)
sys.path.insert(0,str(R/'safevision/tools'))
from audit_v3_resource_checkpoint import sources
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
from v3_sources import snapshot
D=read(B/'design803.json');physical=snapshot(R);assert physical==D['physical_source_sha256']
P=R/'evidence/v3/four_features_261020/acceptance.json';index=read(P);M=R/index['matrix'];matrix=read(M)
assert not index['complete']and len(matrix['positive'])==303 and len(matrix['negative'])==221
index_sha=sha(P);matrix_sha=sha(M);targets=('safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_build_parameters_base.tcl', 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/v3_related_status_capture.v', 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v', 'safevision/rtl/audio/v3_audio_system.v', 'safevision/rtl/media/bmp_parser.v', 'safevision/rtl/media/v3_bmp_normalizer.v', 'safevision/rtl/media/v3_wav_parser_compact_ctx.v', 'safevision/rtl/memory/v3_row_integrity.v', 'safevision/rtl/storage/fat32_directory_scanner.v', 'safevision/rtl/storage/v3_file_streamer_compact_ctx.v', 'safevision/rtl/storage/v3_shared_fs_service.v', 'safevision/rtl/video/v3_line_cache.v', 'safevision/rtl/video/v3_video_display_core.v', 'safevision/tools/check_v3_clock_contract.py', 'safevision/tools/check_v3_command_catalog.py')
positive={r['top']:r for r in index['positive_tests']};negative={r['mutation']:r for r in index['negative_controls']}
lock=threading.Lock();completed=[];started=read(O/'started.json');previous_completed=read(O/'progress.json')['results']

def mutate(row):
 body=(R/row['target']).read_text(encoding='utf-8-sig')
 for patch in row['patch']:
  assert body.count(patch['before'])==patch.get('occurrences',1),(row['mutation'],'semantic patch is not exact')
  body=body.replace(patch['before'],patch['after'])
 return body

def normal(folder,top,is_negative,legacy=False):
 log=(folder/'sim.log').read_text(encoding='utf-8-sig',errors='replace')
 errors=[int(v)for v in re.findall(r'errors\s*=\s*(\d+)',log)]
 marker=re.search(r'\$finish called[^\n]*'+re.escape(top)+r'\.sv\b',log)if legacy else re.search(r'PASS\s+'+re.escape(top)+r'\b|\[TB\]\s*'+re.escape(top)+r'\s+done',log)
 assert '$finish called'in log and marker
 assert not re.search(r'(?im)^\s*(?:\[[^]\n]+\]\s*)?(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log
 if is_negative:assert errors and any(errors)and'[FAIL'in log
 else:assert audit_file(folder/'sim.log',not legacy)['accepted']
 return errors

def validate(kind,row,folder):
 folder=Path(folder);meta=read(folder/('result.json'if kind=='positive'else'case.json'))
 assert meta['top']==row['top']and meta['suite']==row['suite']
 if kind=='positive':
  assert meta['accepted_native_runner']and not meta['source_overrides']
  assert bool(meta['legacy'])==bool(row['legacy'])and meta.get('status','PASS')=='PASS'
  errors=normal(folder,row['top'],False,row['legacy']);count=sources(R,folder);g=graph(R,folder,meta)
 else:
  assert all(meta[k]==row[k]for k in('mutation','target','suite','top','patch'))
  assert meta['original_sha256']==sha(R/row['target'])
  mutant=folder/meta['mutant_file'];assert mutant.read_text(encoding='utf-8-sig')==mutate(row)and sha(mutant)==meta['mutated_sha256']
  assert meta['detected']and meta['normal_completion']and meta.get('process_exit',meta.get('return_code'))==1
  errors=normal(folder,row['top'],True)
  assert errors==meta['error_counts']
  if meta.get('required_marker'):assert meta['required_marker']in(folder/'sim.log').read_text(errors='replace')
  count=sources(R,folder,meta);g=graph(R,folder,dict(top=row['top'],suite=row['suite']),meta)
 return dict(metadata=meta,metadata_sha256=sha(folder/('result.json'if kind=='positive'else'case.json')),normal_completion=True,input_count=count,compiler_graph=g,error_counts=errors,log_sha256=sha(folder/'sim.log'))

plan=[];reused=[]
for kind,definitions in(('positive',matrix['positive']),('negative',matrix['negative'])):
 for definition in definitions:
  name=definition['top']if kind=='positive'else definition['mutation'];entry=(positive if kind=='positive'else negative)[name];folder=R/entry['evidence'];row=dict(definition)
  if kind=='negative':
   old=read(folder/'case.json')
   if old.get('required_marker'):row['required_marker']=old['required_marker']
  capture=read(folder/'sources.sha256.json');affected=any(target in capture for target in targets)
  manifest_path=R/f"safevision/build/manifests/{row['suite']}_sim.json"
  assert not affected or manifest_path.is_file(),('affected suite has no executable manifest',name)
  manifest=read(manifest_path)if manifest_path.is_file()else{}
  item=dict(kind=kind,name=name,row=row,prior_producer=str(folder),rerun_required=affected,duration_priority=manifest.get('timeouts',{}).get(row['top'],600))
  if not affected:
   checked=validate(kind,row,folder);reused.append(dict(kind=kind,name=name,accepted=True,action='unchanged_actual_capture_revalidated',producer_folder=str(folder),checked=checked))
  plan.append(item)
 tasks=[r for r in plan if r['rerun_required']]
 save(O/'planning.progress.json',dict(planned=len(plan),reused=len(reused),fresh_native_required=len(tasks)))
tasks.sort(key=lambda r:r['duration_priority'],reverse=True)
save(O/'plan.json',dict(source_root=str(R),source_commit=D['commit'],required=dict(positive=303,negative=221),source=physical,reused=len(reused),fresh_native_required=len(tasks),records=plan))
print(json.dumps(dict(planned=524,reused=len(reused),fresh_native_required=len(tasks),source_commit=D['commit'])),flush=True)

for old in previous_completed:
 assert old['accepted'],'failed old case needs explicit repair before resume'
 item=next(r for r in tasks if r['kind']==old['kind']and r['name']==old['name'])
 assert validate(old['kind'],item['row'],old['producer_folder'])==old['checked']
 completed.append(old)
already_completed={(r['kind'],r['name'])for r in completed}

def execute(item):
 start=time.monotonic();row=item['row'];kind=item['kind'];name=item['name'];top=row['top'];out=O/kind/name;existing=out.exists();out.mkdir(parents=True,exist_ok=True)
 record=dict(kind=kind,name=name,accepted=False,action='fresh_native_execution',producer_folder=str(out/'sim'/top))
 with lock:
  started.append(dict(kind=kind,name=name,started=time.time()));save(O/'started.json',started)
  print(json.dumps(dict(started=name,kind=kind)),flush=True)
 try:
  assert snapshot(R)==physical
  suite=row['suite'];manifest=read(R/f'safevision/build/manifests/{suite}_sim.json');strict=manifest.get('strict_generated_inputs')==1
  runner='run_legacy_b_fourbeat_sim.py'if suite=='legacy_b_fourbeat'else'run_v3_sim_flexible.py'if strict else'run_v3_sim.py'
  folder=out/'sim'/top
  if not existing:
   if not strict:folder.mkdir(parents=True)
   else:assert not folder.exists(),'strict runner owns the fresh top directory'
  cmd=[sys.executable,'-X','utf8','-B',str(R/'safevision/tools'/runner),'--suite',suite,'--top',top,'--run-dir',str(out/'sim')]
  if kind=='negative':
   mutant=(out/'inputs/mutant.v')if strict else folder/'mutant.v';mutant.parent.mkdir(parents=True,exist_ok=True)
   if existing:assert mutant.read_bytes()==mutate(row).encode()
   else:mutant.write_bytes(mutate(row).encode())
   cmd+=['--override-source',row['target']+'='+str(mutant)]
  if existing:
   assert any(r['kind']==kind and r['name']==name for r in read(O/'started.json')),'unowned preexisting run'
   await_existing_runner(out)
   assert(out/'sim/results.json').is_file(),'existing native runner did not produce normal results'
   wrapper=read(out/'sim/results.json');process=type('Completed',(),{'returncode':0 if wrapper['complete']else 1})()
  else:
   with(out/'runner.console.log').open('wb')as f:
    process=subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=max(7200,item['duration_priority']+600))
  wrapper=read(out/'sim/results.json');assert len(wrapper['results'])==1 and wrapper['suite']==suite
  meta=wrapper['results'][0];assert meta['top']==top
  if kind=='positive':
   assert process.returncode==0 and wrapper['complete']and meta['status']=='PASS'and not meta['source_overrides'],(process.returncode,meta)
   meta.update(suite=suite,legacy=row.get('legacy',False),accepted_native_runner=True,producer_process_exit=0,original_producer=str(folder))
   save(folder/'result.json',meta)
  else:
   assert process.returncode==1 and not wrapper['complete']and meta['status']=='FAIL'and meta['source_overrides']==[row['target']],(process.returncode,meta)
   errors=normal(folder,top,True)
   if strict:shutil.copyfile(mutant,folder/'mutant.v');assert sha(mutant)==sha(folder/'mutant.v')
   case=dict(row,original_sha256=sha(R/row['target']),mutated_sha256=sha(mutant),mutant_file='mutant.v',process_exit=1,return_code=1,normal_completion=True,error_counts=errors,detected=True,producer_folder=str(folder),original_producer=str(folder))
   if strict:case.update(strict_generated_inputs=1,native_runner='safevision/tools/run_v3_sim_flexible.py')
   save(folder/'case.json',case)
  record['checked']=validate(kind,row,folder)
  assert snapshot(R)==physical
  record['accepted']=True
 except BaseException as error:
  record['error']=type(error).__name__+': '+str(error);(out/'exception.txt').write_text(traceback.format_exc(),encoding='utf-8')
 record['elapsed_s']=round(time.monotonic()-start,3)
 with lock:
  completed.append(record);save(O/'progress.json',dict(complete=False,completed=len(completed),required=len(tasks),accepted=sum(r['accepted']for r in completed),results=completed))
  print(json.dumps(dict(completed=len(completed),required=len(tasks),name=name,accepted=record['accepted'],elapsed_s=record['elapsed_s'],error=record.get('error'))),flush=True)
 return record

with concurrent.futures.ThreadPoolExecutor(max_workers=12)as pool:
 futures=[pool.submit(execute,item)for item in tasks if(item['kind'],item['name'])not in already_completed]
 for future in concurrent.futures.as_completed(futures):future.result()
assert snapshot(R)==physical and sha(P)==index_sha and sha(M)==matrix_sha
all_results=reused+completed;complete=len(all_results)==524 and all(r['accepted']for r in all_results)
save(O/'complete.json',dict(complete=complete,source_root=str(R),source_commit=D['commit'],required=dict(positive=303,negative=221),physical_source_sha256=physical,reused=len(reused),fresh_native_executions=len(completed),results=all_results,index_modified=False,source_modified=False,routed_sta_approved=False,bitstream_approved=False,hardware_verified=False))
print(json.dumps(dict(complete=complete,reused=len(reused),fresh_native_executions=len(completed),accepted=sum(r['accepted']for r in all_results))),flush=True)
raise SystemExit(0 if complete else 1)
