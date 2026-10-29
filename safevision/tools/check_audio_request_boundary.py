
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
PARENT='10f5dee11fe0f69878b98b48de00d73cff4eabdf'
SOURCE='safevision/rtl/storage/v3_wav_source.v'
PARENT_SHA='8d7bd4d1c12267aa75144190c7ab6c3c4460c8fc9d72f6c61bad45c80336ad28'
BEFORE=' wire[3:0] requests=found&~fallback&slot_fill&sector_room;'
AFTER=' (* keep="true" *) wire[3:0] requests=found&~fallback&slot_fill&sector_room;'
def check(root):
 old=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+SOURCE])
 if hashlib.sha256(old).hexdigest()!=PARENT_SHA:raise ValueError('frozen WAV source changed')
 text=old.decode('utf-8-sig')
 if text.count(BEFORE)!=1 or(root/SOURCE).read_text('utf-8-sig')!=text.replace(BEFORE,AFTER):raise ValueError('change beyond the single reviewed synthesis attribute')
 rows=[]
 for rr in range(4):
  for mask in range(16):
   r=[bool(mask&(1<<i))for i in range(4)];p0,p1,p2,p3=(rr==i for i in range(4))
   winner=[r[0]and(p0 or(p1 and not any(r[1:]))or(p2 and not any(r[2:]))or(p3 and not r[3])),
    r[1]and(p1 or(p2 and not(r[2]or r[3]or r[0]))or(p3 and not(r[3]or r[0]))or(p0 and not r[0])),
    r[2]and(p2 or(p3 and not(r[3]or r[0]or r[1]))or(p0 and not(r[0]or r[1]))or(p1 and not r[1])),
    r[3]and(p3 or(p0 and not(r[0]or r[1]or r[2]))or(p1 and not(r[1]or r[2]))or(p2 and not r[2]))]
   actual=sum(int(bit)<<i for i,bit in enumerate(winner));expected=0
   for step in range(4):
    index=(rr+step)%4
    if r[index]:expected=1<<index;break
   if actual!=expected:raise ValueError('round-robin winner identity failed')
   chosen=(int(winner[2]or winner[3])<<1)|int(winner[1]or winner[3])
   if actual and actual!=(1<<chosen):raise ValueError('selected index differs from one-hot winner')
   rows.append([rr,mask,actual,chosen,int(bool(mask))])
 return dict(accepted=True,scope='Complete source equals frozen parent plus one non-behavioral synthesis attribute; all64request/priority cases also agree with an independent loop',parent_commit=PARENT,parent_source_sha256=PARENT_SHA,source_sha256=hashlib.sha256((root/SOURCE).read_bytes()).hexdigest(),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),request_priority_cases=len(rows),decision_sha256=hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest(),verilog_operators_state_and_interface_unchanged=True,added_latency_cycles=0,clock_reset_constraints_changed=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('AUDIO REQUEST BOUNDARY '+('PASS'if r['accepted']else'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
