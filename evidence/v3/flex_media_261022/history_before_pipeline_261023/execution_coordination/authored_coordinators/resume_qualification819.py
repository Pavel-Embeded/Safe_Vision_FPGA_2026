"""Resume identical-source native qualification with12 independent workers.

Only the old Python coordinator is stopped. Live native runner subprocesses
remain attached through Windows process handles and finish normally. Every
native log, source graph and semantic mutant is revalidated by the same checker.
"""
from pathlib import Path
import subprocess,json,ctypes,datetime,hashlib
B=Path('D:/Codex/svflex537');O=B/'qualification811';H=O/'coordinator_resume819';H.mkdir(exist_ok=True);assert not(H/'receipt.json').exists()
def ps(code):return subprocess.check_output(['powershell','-NoProfile','-Command',code],text=True,encoding='utf-8-sig')
owners=json.loads(ps("@(Get-CimInstance Win32_Process -Filter \"Name='python.exe'\"|Where-Object {$_.CommandLine -match 'work[\\/]requalify_features811\\.py'}|Select-Object ProcessId,CreationDate,CommandLine)|ConvertTo-Json -Compress")or'[]')
if isinstance(owners,dict):owners=[owners]
assert len(owners)<=1
if owners:
 owner=owners[0];pid=int(owner['ProcessId']);(H/'owner.before.json').write_text(json.dumps(owner,indent=2)+'\n')
else:
 assert(H/'progress.json').is_file()and not(O/'complete.json').exists()
 old=json.loads((B/'active813.processes.json').read_text(encoding='utf-8-sig'));owner=next(r for r in old if 'work/requalify_features811.py'in r.get('CommandLine',''));owner=dict(owner,bootstrap_retry_after_verified_coordinator_stop=True,native_runner_enumeration_error='JSON empty due to path separator regex; no native runner stopped')
for n in ['progress.json','plan.json','started.json']:
 p=O/n;assert p.is_file()
 if not(H/n).exists():(H/n).write_bytes(p.read_bytes())
if owners:ps("$p=Get-CimInstance Win32_Process -Filter 'ProcessId="+str(pid)+"';if($p.Name -ne 'python.exe' -or $p.CommandLine -notmatch 'work[\\/]requalify_features811\\.py'){throw 'Coordinator identity changed'};Stop-Process -Id "+str(pid))
running=json.loads(ps("@(Get-CimInstance Win32_Process -Filter \"Name='python.exe'\"|Where-Object {$_.CommandLine.Replace([char]92,[char]47).Contains('svflex537/qualification811/') -and $_.CommandLine -match 'run_v3_sim'}|Select-Object ProcessId,CreationDate,CommandLine)|ConvertTo-Json -Compress")or'[]')
if isinstance(running,dict):running=[running]
running=running or []
k=ctypes.WinDLL('kernel32',use_last_error=True);k.OpenProcess.argtypes=[ctypes.c_uint,ctypes.c_int,ctypes.c_uint];k.OpenProcess.restype=ctypes.c_void_p;k.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint];k.WaitForSingleObject.restype=ctypes.c_uint;k.CloseHandle.argtypes=[ctypes.c_void_p]
handles=[]
for r in running:
 h=k.OpenProcess(0x100000,False,int(r['ProcessId']));assert h,'Could not attach live native runner';handles.append((r,h))
(H/'receipt.json').write_text(json.dumps(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),old_coordinator_only_stopped=owner,live_native_runners_preserved=running,new_workers=12,source_commit='821535a2900eea9951a8c399a6a7f128bc25f852',native_cases_not_cancelled=True,source_index_matrix_not_modified=True),indent=2)+'\n')
original=Path('work/requalify_features811.py').read_text()
original=original.replace("if O.exists():assert not any(O.iterdir()),'choose a fresh output; no evidence is overwritten'\nelse:O.mkdir()","assert O.is_dir()and(O/'coordinator_resume819/receipt.json').is_file()")
original=original.replace("lock=threading.Lock();completed=[];started=[]","lock=threading.Lock();completed=[];started=read(O/'started.json');previous_completed=read(O/'progress.json')['results']")
anchor="def execute(item):";assert original.count(anchor)==1
original=original.replace(anchor,"""for old in previous_completed:
 assert old['accepted'],'failed old case needs explicit repair before resume'
 item=next(r for r in tasks if r['kind']==old['kind']and r['name']==old['name'])
 assert validate(old['kind'],item['row'],old['producer_folder'])==old['checked']
 completed.append(old)
already_completed={(r['kind'],r['name'])for r in completed}

def execute(item):""")
original=original.replace("out=O/kind/name;out.mkdir(parents=True,exist_ok=False)","out=O/kind/name;existing=out.exists();out.mkdir(parents=True,exist_ok=True)")
original=original.replace("if not strict:folder.mkdir(parents=True)\n  else:assert not folder.exists(),'strict runner owns the fresh top directory'","if not existing:\n   if not strict:folder.mkdir(parents=True)\n   else:assert not folder.exists(),'strict runner owns the fresh top directory'")
original=original.replace("mutant.parent.mkdir(parents=True,exist_ok=True);mutant.write_bytes(mutate(row).encode())","mutant.parent.mkdir(parents=True,exist_ok=True)\n   if existing:assert mutant.read_bytes()==mutate(row).encode()\n   else:mutant.write_bytes(mutate(row).encode())")
anchor="  with(out/'runner.console.log').open('wb')as f:\n   process=subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=max(7200,item['duration_priority']+600))"
replacement="""  if existing:
   assert any(r['kind']==kind and r['name']==name for r in read(O/'started.json')),'unowned preexisting run'
   await_existing_runner(out)
   assert(out/'sim/results.json').is_file(),'existing native runner did not produce normal results'
   wrapper=read(out/'sim/results.json');process=type('Completed',(),{'returncode':0 if wrapper['complete']else 1})()
  else:
   with(out/'runner.console.log').open('wb')as f:
    process=subprocess.run(cmd,cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=max(7200,item['duration_priority']+600))"""
assert original.count(anchor)==1;original=original.replace(anchor,replacement)
original=original.replace('max_workers=4','max_workers=12').replace('futures=[pool.submit(execute,item)for item in tasks]','futures=[pool.submit(execute,item)for item in tasks if(item[\'kind\'],item[\'name\'])not in already_completed]')
def await_existing_runner(out):
 marker=str(out).lower().replace('/','\\')
 match=[(r,h)for r,h in handles if marker in r['CommandLine'].lower().replace('/','\\')]
 assert len(match)<=1
 if match:assert k.WaitForSingleObject(match[0][1],7800000)==0,'native runner wait timeout'
(H/'executed_coordinator.py').write_bytes(original.encode())
try:exec(compile(original,str(H/'executed_coordinator.py'),'exec'),dict(__name__='__main__',__file__=str(H/'executed_coordinator.py'),await_existing_runner=await_existing_runner))
finally:
 for r,h in handles:k.CloseHandle(h)
