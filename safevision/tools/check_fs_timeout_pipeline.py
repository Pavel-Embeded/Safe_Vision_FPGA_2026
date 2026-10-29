"""Bind the timeout-only pipeline and exhaust its byte-acceptance protocol."""
from pathlib import Path
from collections import deque
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
SOURCE='safevision/rtl/storage/v3_file_streamer_compact_ctx.v'
CALLER='safevision/rtl/storage/v3_shared_fs_service.v'
MODEL='safevision/verification/models/v3_file_streamer_frozen_timeout.sv'
META='safevision/verification/models/v3_file_streamer_frozen_timeout.freeze.json'
PARENT='1032da511ded4321ffb8047603a57ae5b084b5ac'
ORIGINAL_SHA='fffd4d7366dc95f31f9ef6c16589b618ed3f2c34deb90c0d83e167eed09d755a'
PATCHES=[('DIRECT_REQUEST_ADDRESS=0,PIPELINED_LBA=0) (', 'DIRECT_REQUEST_ADDRESS=0,PIPELINED_LBA=0,REGISTERED_TIMEOUT_EDGE=0) ('), ('    wire last_file_byte=next_count==fsize;', '    wire last_file_byte=next_count==fsize;\n    // The timeout branch uses this predicate only on accepted sector byte511.\n    // An accepted byte raises valid, preventing another acceptance on the\n    // following edge. The registered predicate is therefore current at use.\n    // Context loads reset bcnt to0; legacy/library mode keeps its old path.\n    (* keep="true" *) reg timeout_last_q;\n    always @(posedge clk or negedge rst_n)\n      if(!rst_n)timeout_last_q<=1\'b0;\n      else timeout_last_q<=last_file_byte;\n    wire timeout_last=REGISTERED_TIMEOUT_EDGE?timeout_last_q:last_file_byte;'), ('bcnt==511&&!stop_pending&&!last_file_byte&&', 'bcnt==511&&!stop_pending&&!timeout_last&&')]
CALL_BEFORE='.PIPELINED_LBA(FLEX_FILES)) fs('
CALL_AFTER='.PIPELINED_LBA(FLEX_FILES),.REGISTERED_TIMEOUT_EDGE(FLEX_FILES)) fs('
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def explore(bubble=True):
 # mode0idle,1request,2receive,3terminal; age is edges since cnt/fsize write.
 initial=(0,0,0,0,0);queue=deque([initial]);seen={initial};depth={initial:0};eligible=0
 while queue:
  state=queue.popleft();mode,b,valid,stop,age=state;later=min(2,age+1)
  if mode==2 and b==511 and not valid and not stop:
   eligible+=1
   if age<1:return dict(accepted=False,states=len(seen),eligible_states=eligible,witness=list(state),witness_depth=depth[state])
  successors={(0,0,0,0,0),(1,0,0,0,0)} # reset/start/context load reset bcnt.
  for enabled in(0,1):
   for ready in(0,1):
    nv=valid and not(enabled and ready)
    successors.add((mode,b,int(nv),stop,later))
    if not enabled:continue
    if mode==0:successors.add((1,0,0,0,0))
    elif mode==1 and not valid:successors.add((2,0,0,stop,later))
    elif mode==3:successors.add((0,b,int(nv),stop,later))
    elif mode==2:
     successors.add((3,b,int(nv),stop,later)) # SD/CRC/timeout error.
     if not valid:
      for last in(0,1):
       ns=stop or last;na=later if stop else 0;outvalid=0 if stop else int(bubble)
       nm=mode if b!=511 else(3 if ns else 1)
       successors.add((nm,(b+1)%512,outvalid,int(ns),na))
  for nxt in successors:
   if nxt not in seen:seen.add(nxt);depth[nxt]=depth[state]+1;queue.append(nxt)
 return dict(accepted=True,states=len(seen),eligible_states=eligible)
def check(root):
 meta=json.loads((root/META).read_text('utf-8-sig'));old=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+SOURCE])
 if meta['parent_commit']!=PARENT or hashlib.sha256(old).hexdigest()!=ORIGINAL_SHA or meta['source_sha256']!=ORIGINAL_SHA:raise ValueError('original compact kernel changed')
 frozen=old.replace(b'module v3_file_streamer_compact_ctx #(',b'module v3_file_streamer_frozen_timeout #(')
 if(root/MODEL).read_bytes()!=frozen or sha(root/MODEL)!=meta['reference_sha256']:raise ValueError('frozen kernel differs beyond its declaration')
 expected=old.decode('utf-8-sig')
 for before,after in PATCHES:
  if expected.count(before)!=1:raise ValueError('pipeline transform anchor changed')
  expected=expected.replace(before,after)
 if(root/SOURCE).read_text('utf-8-sig')!=expected:raise ValueError('unreviewed compact kernel edit')
 caller=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+CALLER]).decode('utf-8-sig')
 if caller.count(CALL_BEFORE)!=1 or(root/CALLER).read_text('utf-8-sig')!=caller.replace(CALL_BEFORE,CALL_AFTER):raise ValueError('production selection or shared service changed')
 normal=explore(True);broken=explore(False)
 if not normal['accepted']or normal['eligible_states']==0 or broken['accepted']:raise ValueError('byte-spacing temporal proof failed')
 return dict(accepted=True,scope='Complete-source binding plus exhaustive abstract protocol exploration; actual native simulation and routed STA are separate',source_sha256=sha(root/SOURCE),caller_sha256=sha(root/CALLER),model_sha256=sha(root/MODEL),metadata_sha256=sha(root/META),tool_sha256=sha(Path(__file__)),normal_protocol=normal,no_bubble_contract_control=broken,counter_and_size_values_symbolically_arbitrary=True,public_data_and_latency_unchanged=True,timeout_threshold_unchanged=True,only_use_guard='F_SEC_RECV && bcnt511 && !valid && !stop_pending && accepted_SD_byte',new_timing_exception=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('FS TIMEOUT PROTOCOL '+('PASS'if r['accepted']else'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
