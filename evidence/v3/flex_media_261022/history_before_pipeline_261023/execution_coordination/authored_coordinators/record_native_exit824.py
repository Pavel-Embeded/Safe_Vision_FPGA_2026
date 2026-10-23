"""Record actual Windows exits of native runners kept alive across coordinator resume."""
from pathlib import Path
import ctypes,json,re,datetime
B=Path('D:/Codex/svflex537');O=B/'qualification811/coordinator_resume819';data=json.loads((O/'receipt.json').read_text());k=ctypes.WinDLL('kernel32',use_last_error=True)
k.OpenProcess.argtypes=[ctypes.c_uint,ctypes.c_int,ctypes.c_uint];k.OpenProcess.restype=ctypes.c_void_p;k.WaitForSingleObject.argtypes=[ctypes.c_void_p,ctypes.c_uint];k.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_uint)];k.CloseHandle.argtypes=[ctypes.c_void_p]
class FT(ctypes.Structure):_fields_=[('low',ctypes.c_uint),('high',ctypes.c_uint)]
k.GetProcessTimes.argtypes=[ctypes.c_void_p,*([ctypes.POINTER(FT)]*4)]
handles=[]
for row in data['live_native_runners_preserved']:
 h=k.OpenProcess(0x101000,False,row['ProcessId']);assert h,'Original native runner identity no longer available'
 created,exited,kernel,user=FT(),FT(),FT(),FT();assert k.GetProcessTimes(h,ctypes.byref(created),ctypes.byref(exited),ctypes.byref(kernel),ctypes.byref(user))
 actual=((created.high<<32)+created.low)//10000-11644473600000;expected=int(re.search(r'\d+',row['CreationDate'])[0]);assert abs(actual-expected)<=1,'Native runner PID reused'
 handles.append((row,h))
records=[]
try:
 for row,h in handles:
  assert k.WaitForSingleObject(h,7800000)==0,'Native runner did not exit'
  code=ctypes.c_uint();assert k.GetExitCodeProcess(h,ctypes.byref(code));records.append(dict(**row,actual_process_exit=code.value,normal_success=code.value==0))
  (O/'actual_native_exits.json').write_text(json.dumps(dict(complete=False,records=records),indent=2)+'\n')
 assert len(records)==4 and all(r['normal_success']for r in records)
 (O/'actual_native_exits.json').write_text(json.dumps(dict(complete=True,records=records,utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),process_creation_identity_checked=True),indent=2)+'\n');print('Four original native runner OS exits confirmed0; identities matched creation time.',flush=True)
finally:
 for row,h in handles:k.CloseHandle(h)
