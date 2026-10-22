"""Preserve in-flight native runs when the outer scheduler budget is too short.

Only this task's own coordinator is suspended. Its native child runners retain
their original test limits and all assertions. Actual child exit codes are
captured with process handles; queued tests run under a corrected coordinator.
"""
from pathlib import Path
import ctypes,json,subprocess,sys,hashlib,time,concurrent.futures,threading,shutil,re
B=Path('D:/Codex/svmultires510');S=B/'source';O=B/'scheduler_recovery';O.mkdir()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
save=lambda p,j:p.write_text(json.dumps(j,indent=2)+'\n',encoding='utf-8')
cmd="Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'python.exe' -and ($_.CommandLine -like '*regress_multires510.py*' -or $_.CommandLine -like '*svmultires510*run_v3_sim.py*')} | Select-Object ProcessId,ParentProcessId,CommandLine,CreationDate | ConvertTo-Json -Depth 4 -Compress"
rows=json.loads(subprocess.check_output(['powershell','-NoProfile','-Command',cmd],text=True));assert isinstance(rows,list)
parents=[r for r in rows if 'regress_multires510.py'in r['CommandLine']];assert len(parents)==1;parent=parents[0]
children=[r for r in rows if r['ParentProcessId']==parent['ProcessId']];assert children and len(children)<=4
k=ctypes.WinDLL('kernel32',use_last_error=True);nt=ctypes.WinDLL('ntdll')
k.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32];k.OpenProcess.restype=ctypes.c_void_p
k.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint32];k.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint32)]
k.CloseHandle.argtypes=[ctypes.c_void_p];k.TerminateProcess.argtypes=[ctypes.c_void_p,ctypes.c_uint32]
nt.NtSuspendProcess.argtypes=[ctypes.c_void_p];nt.NtResumeProcess.argtypes=[ctypes.c_void_p]
hparent=k.OpenProcess(0x0800|0x1000|0x100000|1,0,parent['ProcessId']);assert hparent
handles={r['ProcessId']:k.OpenProcess(0x1000|0x100000,0,r['ProcessId'])for r in children};assert all(handles.values())
assert nt.NtSuspendProcess(hparent)==0
save(O/'process_identity.json',dict(coordinator=parent,children=children,observer_sha256=sha(Path(__file__)),reason='Outer1800s is shorter than the existing native maximum-card5400s limit. Preserve all live native runners and their complete assertions; only replace scheduling/waiting.'))
original_progress=read(B/'regression/progress.json');completed={r['name']for r in original_progress['results']}
allrows=read(B/'affected.json');active={}
for r in allrows['positive']:
 path=B/'regression/positive'/r['top']
 if path.exists()and r['top']not in completed:
  match=[c for c in children if str(path/'sim').casefold().replace('/','\\')in c['CommandLine'].casefold().replace('/','\\')]
  assert len(match)==1,(r['top'],children);active[r['top']]=(r,path,match[0])
assert len(active)==len(children)
# Reuse the same case runner, source/graph checks and final matrix update.
text=(Path(__file__).parent/'regress_multires510.py').read_text(encoding='utf-8')
prefix=text.split("tasks=[('positive'",1)[0]
prefix=prefix.replace("O=B/'regression';O.mkdir()","O=B/'regression_recovered';O.mkdir()")
prefix=prefix.replace('results=[]',"results=json.loads((B/'regression/progress.json').read_text())['results']")
prefix=prefix.replace('timeout=1800','timeout=7200')
ctx={'__file__':str(Path(__file__)),'__name__':'recovered_cases'};exec(compile(prefix,'recovered_cases','exec'),ctx)
results=ctx['results'];lock=ctx['lock'];run=ctx['run'];N=ctx['O']
sys.path.insert(0,str(S/'safevision/tools'));from check_v3_sim_graph import check as graph
from audit_v3_resource_checkpoint import sources as source_check
def observe():
 for name,(row,out,child)in active.items():
  handle=handles[child['ProcessId']];started=time.monotonic()
  while k.WaitForSingleObject(handle,1000)==258:
   if time.monotonic()-started>7200:raise TimeoutError('Native runner exceeded its own bounded wait')
  code=ctypes.c_uint32();assert k.GetExitCodeProcess(handle,ctypes.byref(code))and code.value==0,(name,code.value)
  report=read(out/'sim/results.json');assert report['complete']and len(report['results'])==1
  meta=report['results'][0];assert meta['status']=='PASS'and not meta['source_overrides'];folder=out/'sim'/name
  log=(folder/'sim.log').read_text(encoding='utf-8',errors='replace');assert '$finish called'in log and '[PASS]'in log and not re.search(r'\[FAIL\]|\[SKIP\]|(?im:^\s*(?:FATAL|Fatal:|ERROR:))',log)
  dest=S/'evidence/v3/multires_alias_261022/positive'/name;dest.mkdir(parents=True)
  for p in folder.iterdir():
   if p.is_file()and p.suffix in('.log','.json','.prj','.mem','.hex'):shutil.copyfile(p,dest/p.name)
  meta.update(suite=row['suite'],legacy=row['legacy'],accepted_native_runner=True,producer_process_exit=0,original_producer=str(folder),native_runner_exit_captured_by_process_handle=True,scheduler_recovered=True)
  save(dest/'result.json',meta);source_check(S,dest);graph(S,dest,meta)
  result=dict(kind='positive',name=name,accepted=True,evidence=dest.relative_to(S).as_posix(),result_sha256=sha(dest/'result.json'))
  with lock:
   results.append(result);save(N/'progress.json',dict(completed=len(results),required=153,results=results));print(json.dumps(dict(recovered=name,actual_native_runner_exit=code.value,completed=len(results))),flush=True)
  k.CloseHandle(handle)
 assert k.TerminateProcess(hparent,0xC000013A)
 k.CloseHandle(hparent);save(O/'native_children.json',dict(accepted=True,all_native_runner_exits_zero=True,recovered_cases=sorted(active),coordinator_terminated_after_all_native_children_finished=True,assertions_clocks_sources_unchanged=True))
tasks=[('positive',r)for r in allrows['positive']]+[('negative',r)for r in allrows['negative']]
tasks=[(kind,r)for kind,r in tasks if (r['top']if kind=='positive'else r['mutation'])not in completed and not(kind=='positive'and r['top']in active)]
print(json.dumps(dict(live_native_runs_preserved=sorted(active),queued_cases=len(tasks),completed_before=len(results))),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=5)as pool:
 futures=[pool.submit(observe)]+[pool.submit(run,kind,row)for kind,row in tasks]
 for f in concurrent.futures.as_completed(futures):f.result()
assert len(results)==153 and len({(r['kind'],r['name'])for r in results})==153
suffix=text.split('maps={(r[',1)[1];suffix='maps={(r['+suffix
suffix=suffix.replace("save(O/'complete.json'","save(B/'regression/complete.json'")
ctx.update(results=results);exec(compile(suffix,'recovered_final_matrix','exec'),ctx)
dest=S/'evidence/v3/multires_alias_261022/scheduler_recovery';shutil.copytree(O,dest);shutil.copyfile(Path(__file__),dest/Path(__file__).name)
print('Recovered scheduling; all native regressions genuinely completed',flush=True)
