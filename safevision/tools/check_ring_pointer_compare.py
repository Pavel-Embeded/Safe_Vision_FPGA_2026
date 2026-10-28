"""Prove direct FIFO predicates over all reachable binary pointer states."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(root):
 source='safevision/rtl/audio/v3_pcm_ring.v';model='safevision/verification/models/v3_pcm_ring_frozen_pointer.sv'
 meta=json.loads((root/'safevision/verification/models/v3_pcm_ring_frozen_pointer.freeze.json').read_text('utf-8-sig'))
 if(meta['parent_commit'],meta['source_path'],meta['reference_path'],meta['rename_from'],meta['rename_to'])!=('6d2232c839b48484bd9b0eaddd1a268cd546dd44',source,model,'module v3_pcm_ring #(','module v3_pcm_ring_frozen_pointer #('):raise ValueError('ring reference identity differs')
 old=subprocess.check_output(['git','-C',str(root),'cat-file','blob',meta['parent_commit']+':'+source])
 if hashlib.sha256(old).hexdigest()!=meta['source_sha256']or old.count(meta['rename_from'].encode())!=1:raise ValueError('ring parent bytes differ')
 if(root/model).read_bytes()!=old.replace(meta['rename_from'].encode(),meta['rename_to'].encode())or sha(root/model)!=meta['reference_sha256']:raise ValueError('ring reference differs beyond its module declaration')
 expected=old.decode('utf-8-sig')
 patches=[('parameter integer PTR_W=14,PREFETCH=800','parameter integer PTR_W=14,PREFETCH=800,DIRECT_POINTER_COMPARE=0'),('reg [PTR_W:0] wp[0:3],rp[0:3];wire [PTR_W:0] count[0:3];','reg [PTR_W:0] wp[0:3],rp[0:3];wire [PTR_W:0] count[0:3];\n wire[3:0] pointer_empty,pointer_full;'),('assign prefetched[g]=count[g]>=PREFETCH;','assign pointer_empty[g]=(wp[g]==rp[g]);\n  assign pointer_full[g]=(wp[g]=={~rp[g][PTR_W],rp[g][PTR_W-1:0]});\n  assign prefetched[g]=count[g]>=PREFETCH;'),('in_valid[j]&&count[j]<CAP','in_valid[j]&&(DIRECT_POINTER_COMPARE?!pointer_full[j]:count[j]<CAP)'),('count[active]!=0&&!out_valid','(DIRECT_POINTER_COMPARE?!pointer_empty[active]:count[active]!=0)&&!out_valid')]
 for before,after in patches:
  if expected.count(before)!=1:raise ValueError('ring source patch is ambiguous')
  expected=expected.replace(before,after)
 if(root/source).read_text('utf-8-sig')!=expected:raise ValueError('ring changed beyond the reviewed predicate-only transformation')
 selected={source:sha(root/source)}
 for path,changes in [
  ('safevision/rtl/audio/v3_audio_system.v',[('HANDBOOK_PROFILE=0,PREINDEXED=0)(', 'HANDBOOK_PROFILE=0,PREINDEXED=0,DIRECT_RING_COMPARE=0)('),('v3_pcm_ring #(.PREFETCH(PREFETCH)) ring(', 'v3_pcm_ring #(.PREFETCH(PREFETCH),.DIRECT_POINTER_COMPARE(DIRECT_RING_COMPARE)) ring(')]),
  ('safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v',[('v3_audio_system #(.PREINDEXED(1),.EXTERNAL_SERVICE(1)', 'v3_audio_system #(.DIRECT_RING_COMPARE(TICKER_ENABLE),.PREINDEXED(1),.EXTERNAL_SERVICE(1)')])]:
  prior=subprocess.check_output(['git','-C',str(root),'cat-file','blob',meta['parent_commit']+':'+path]).decode('utf-8-sig')
  for before,after in changes:
   if prior.count(before)!=1:raise ValueError('ring integration anchor differs')
   prior=prior.replace(before,after)
  if(root/path).read_text('utf-8-sig')!=prior:raise ValueError('ring integration changed beyond its parameter wiring')
  selected[path]=sha(root/path)
 result=[];matrix=hashlib.sha256()
 # For fixed high bits, every expression depends on lower words only through
 # their signed difference. All translations of a lower-word pair have the
 # same result. CAP-abs(delta) is the exact number of represented pairs.
 for width in range(4,15):
  cap=1<<width;mask=2*cap-1;classes=legal_pairs=all_pairs=0
  for high_w in(0,1):
   for high_r in(0,1):
    for delta in range(1-cap,cap):
     low_w=max(delta,0);low_r=max(-delta,0)
     wp=high_w*cap+low_w;rp=high_r*cap+low_r;count=(wp-rp)&mask
     empty=wp==rp;full=wp==(rp^cap);weight=cap-abs(delta)
     if empty!=(count==0)or full!=(count==cap):raise ValueError('pointer equality differs from modular count')
     if count<=cap:
      if(not empty)!=(count!=0)or(not full)!=(count<cap):raise ValueError('reachable scheduling predicate differs')
      legal_pairs+=weight
     all_pairs+=weight;classes+=1
     matrix.update(bytes((width,high_w,high_r,int(empty),int(full),int(count<=cap))))
  if all_pairs!=4*cap*cap or legal_pairs!=2*cap*(cap+1):raise ValueError('compressed exhaustive domain coverage differs')
  result.append(dict(pointer_bits=width,capacity=cap,difference_classes=classes,all_binary_pointer_pairs=all_pairs,reachable_pointer_pairs=legal_pairs))
 return dict(accepted=True,scope='Mathematical binary-state proof and exact predicate-only source identity; native timing and board acceptance are separate',invariant='0 <= modular(wp-rp) <= CAP',invariant_basis='Reset sets equal pointers; serialized completed reads only when nonempty and completed writes only when not full preserve the bound',original_arithmetic_status_unchanged=True,request_latency_unchanged=True,default_parameter_behavior_preserved=True,widths=result,decision_sha256=matrix.hexdigest(),source_sha256=sha(root/source),selected_source_sha256=selected,model_sha256=sha(root/model),tool_sha256=sha(Path(__file__)))
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('RING POINTER DOMAIN '+('PASS'if r['accepted']else'FAILED '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
