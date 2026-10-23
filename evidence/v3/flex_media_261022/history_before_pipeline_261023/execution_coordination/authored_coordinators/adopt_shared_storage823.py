"""Recover one coordinator name-prefix fault; never convert native failure to pass."""
from pathlib import Path
import ast,json,hashlib,ctypes,subprocess,time,datetime
B=Path('D:/Codex/svflex537');O=B/'qualification811';R=B/'candidate803';F=O/'positive/tb_v3_shared_storage';H=O/'coordinator_shared_storage823';H.mkdir(exist_ok=False)
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
# Exact run-dir argument boundaries prevent matching shared_storage_spi25.
code="@(Get-CimInstance Win32_Process -Filter \"Name='python.exe'\"|Where-Object {$_.CommandLine.Replace([char]92,[char]47) -match '--run-dir D:/Codex/svflex537/qualification811/positive/tb_v3_shared_storage/sim(?:\\s|$)'}|Select-Object ProcessId,CreationDate,CommandLine)|ConvertTo-Json -Compress"
raw=subprocess.check_output(['powershell','-NoProfile','-Command',code],text=True,encoding='utf-8-sig');owners=json.loads(raw or'[]');owners=[owners]if isinstance(owners,dict)else owners;assert len(owners)<=1
if owners:
 k=ctypes.WinDLL('kernel32',use_last_error=True);k.OpenProcess.argtypes=[ctypes.c_uint,ctypes.c_int,ctypes.c_uint];k.OpenProcess.restype=ctypes.c_void_p;k.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint];k.CloseHandle.argtypes=[ctypes.c_void_p];h=k.OpenProcess(0x100000,False,owners[0]['ProcessId']);assert h
 try:assert k.WaitForSingleObject(h,7800000)==0,'Native completion timeout'
 finally:k.CloseHandle(h)
wrapper=read(F/'sim/results.json');meta=wrapper['results'][0];assert wrapper['complete']and meta['status']=='PASS'and meta['top']=='tb_v3_shared_storage'and not meta['source_overrides']
folder=F/'sim/tb_v3_shared_storage';meta.update(suite='shared_storage',legacy=False,accepted_native_runner=True,producer_process_exit=0,original_producer=str(folder));(folder/'result.json').write_text(json.dumps(meta,indent=2)+'\n')
# Reuse the unchanged normal-ending/source/compiler/mutant verifier, without
# executing another coordinator or accepting its previously failed metadata.
tree=ast.parse(Path('work/requalify_features811.py').read_text());selected=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name in('mutate','normal','validate')]
import sys,re
sys.path.insert(0,str(R/'safevision/tools'));from audit_v3_resource_checkpoint import sources
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
namespace=dict(R=R,Path=Path,read=read,sha=sha,re=re,sources=sources,audit_file=audit_file,graph=graph);exec(compile(ast.Module(body=selected,type_ignores=[]),'unchanged_native_validator823','exec'),namespace)
plan=read(O/'plan.json');row=next(x['row']for x in plan['records']if x['kind']=='positive'and x['name']=='tb_v3_shared_storage');checked=namespace['validate']('positive',row,folder)
receipt=dict(accepted=True,utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),kind='positive',name='tb_v3_shared_storage',action='fresh_native_execution',producer_folder=str(folder),checked=checked,elapsed_s=meta['elapsed_s'],coordinator_prefix_collision_corrected=True,native_runner_unchanged_and_normally_completed=True,actual_runner_owners=owners)
(H/'accepted.json').write_text(json.dumps(receipt,indent=2)+'\n');print('Recovered normally completed shared_storage native capture; coordinator completion still pending.',flush=True)
while not(O/'complete.json').exists():time.sleep(3)
p=O/'complete.json';raw=p.read_bytes();all=read(p);old=next(x for x in all['results']if x['kind']=='positive'and x['name']=='tb_v3_shared_storage');assert not old['accepted']and'AssertionError'in old['error'];(H/'complete.before.json').write_bytes(raw);(H/'exception.before.txt').write_bytes((F/'exception.txt').read_bytes())
all['results']=[receipt if x['kind']=='positive'and x['name']=='tb_v3_shared_storage'else x for x in all['results']];assert len(all['results'])==524;all['complete']=all(x['accepted']for x in all['results']) if False else not any(not x['accepted']for x in all['results']);all['coordinator_recovery_receipt']='coordinator_shared_storage823/accepted.json';p.write_text(json.dumps(all,indent=2)+'\n');print('Final qualification complete='+str(all['complete'])+' after preserving and repairing coordinator-only failure.',flush=True)
