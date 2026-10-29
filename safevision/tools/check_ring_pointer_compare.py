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
 actual_source=(root/source).read_text('utf-8-sig')
 registered_occupancy='begin:registered_level'in actual_source
 if registered_occupancy:
  prior_level="  (* use_ripple=1 *) wire[PTR_W:0] occupancy=wp[slot_index]-rp[slot_index];\n  assign count[slot_index]=occupancy;\n"
  counter_level="""  if(DIRECT_POINTER_COMPARE)begin:registered_level
   // This state changes on exactly the same edges as the two pointers.
   // Reset establishes value=wp-rp modulo2*CAP. The shared increment and
   // decrement events preserve that identity without adding status latency.
   reg[PTR_W:0] value;
   always @(posedge clk or negedge rst_n)
    if(!rst_n)value<=0;
    else if(owner==slot_index && (take_read || finish_write))
     // take_read implies reading=1; finish_write implies reading=0.
     // The two events are exclusive, so this is one signed +/-1 adder.
     value<=value+{{PTR_W{reading}},1'b1};
   assign count[slot_index]=value;
  end else begin:arithmetic_level
   (* use_ripple=1 *) wire[PTR_W:0] occupancy=wp[slot_index]-rp[slot_index];
   assign count[slot_index]=occupancy;
  end
"""
  if expected.count(prior_level)!=1:raise ValueError('occupancy transform anchor differs')
  expected=expected.replace(prior_level,counter_level)
 if actual_source!=expected:raise ValueError('ring changed beyond reviewed pointer predicates and exact occupancy events')
 selected={source:sha(root/source)}
 for path,changes in [
  ('safevision/rtl/audio/v3_audio_system.v',[('HANDBOOK_PROFILE=0,PREINDEXED=0)(', 'HANDBOOK_PROFILE=0,PREINDEXED=0,DIRECT_RING_COMPARE=0)('),('v3_pcm_ring #(.PREFETCH(PREFETCH)) ring(', 'v3_pcm_ring #(.PREFETCH(PREFETCH),.DIRECT_POINTER_COMPARE(DIRECT_RING_COMPARE)) ring(')]),
  ('safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v',[('v3_audio_system #(.PREINDEXED(1),.EXTERNAL_SERVICE(1)', 'v3_audio_system #(.DIRECT_RING_COMPARE(TICKER_ENABLE),.PREINDEXED(1),.EXTERNAL_SERVICE(1)')])]:
  prior=subprocess.check_output(['git','-C',str(root),'cat-file','blob',meta['parent_commit']+':'+path]).decode('utf-8-sig')
  for before,after in changes:
   if prior.count(before)!=1:raise ValueError('ring integration anchor differs')
   prior=prior.replace(before,after)
  if path=='safevision/rtl/audio/v3_audio_system.v' and 'PREFILL_PIPELINE=DIRECT_RING_COMPARE' in(root/path).read_text('utf-8-sig'):
   from check_prefill_pipeline import check as prefill_check,transform as prefill_transform,PARENT as prefill_parent
   prefill_proof=prefill_check(root)
   prefill_original=subprocess.check_output(['git','-C',str(root),'cat-file','blob',prefill_parent+':'+path]).decode('utf-8-sig')
   if not prefill_proof['accepted']or prefill_original!=prior:raise ValueError('prefill parent is not the exact ring integration')
   prior=prefill_transform(prior)
  if(root/path).read_text('utf-8-sig')!=prior:
   if path!='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v':raise ValueError('ring integration changed beyond its parameter wiring')
   # Compose two complete frozen transformations. The row-index parent TOP
   # must equal the already reconstructed audio TOP byte for byte; its seven
   # reviewed edits are then independently checked in full before acceptance.
   from check_direct_row_lookup import check as check_direct,PARENT as direct_parent,META as direct_meta
   proof=check_direct(root)
   row_parent=subprocess.check_output(['git','-C',str(root),'cat-file','blob',direct_parent+':'+path]).decode('utf-8-sig').replace('\r\n','\n')
   if not proof['accepted']or row_parent!=prior:raise ValueError('direct-row parent is not the exact audio integration')
   direct=json.loads((root/direct_meta).read_text('utf-8-sig'))
   for patch in direct['files'][path]['patches']:
    if prior.count(patch['before'])!=patch['occurrences']:raise ValueError('composed integration anchor differs')
    prior=prior.replace(patch['before'],patch['after'])
   if(root/path).read_text('utf-8-sig')!=prior and '.EXTERNAL_FONT(0),.PACKED_EXTERNAL(0),.MESSAGE_CHARS(32)'in(root/path).read_text('utf-8-sig'):
    from check_dedicated_font import check as dedicated_check,parent_top,transform as dedicated_transform
    dedicated=dedicated_check(root)
    if not dedicated['accepted']or parent_top(root)!=prior:raise ValueError('dedicated parent is not exact composed audio/direct-row TOP')
    prior=dedicated_transform(prior)
   if(root/path).read_text('utf-8-sig')!=prior:raise ValueError('unreviewed change after complete audio/direct-row/font composition')
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
      # Reset sets value=wp-rp=0. For either permitted event, the exact
      # signed update and the changed pointer preserve this equality.
      # owner selects the same one of four slots in BOTH state blocks.
      for reading in(0,1):
       if reading and count==0 or not reading and count==cap:continue
       next_wp=wp if reading else (wp+1)&mask
       next_rp=(rp+1)&mask if reading else rp
       signed_step=mask if reading else 1
       next_count=(count+signed_step)&mask
       if next_count!=((next_wp-next_rp)&mask)or not 0<=next_count<=cap:raise ValueError('occupancy induction differs')
      legal_pairs+=weight
     all_pairs+=weight;classes+=1
     matrix.update(bytes((width,high_w,high_r,int(empty),int(full),int(count<=cap))))
  if all_pairs!=4*cap*cap or legal_pairs!=2*cap*(cap+1):raise ValueError('compressed exhaustive domain coverage differs')
  result.append(dict(pointer_bits=width,capacity=cap,difference_classes=classes,all_binary_pointer_pairs=all_pairs,reachable_pointer_pairs=legal_pairs))
 return dict(accepted=True,scope='Mathematical binary-state and occupancy induction proof with complete source identity; native timing and board acceptance are separate',registered_occupancy=registered_occupancy,occupancy_induction='Reset equality; exclusive accepted read or completed write updates the same owner and exact signed modular delta; other slots and idle edges retain state',invariant='0 <= modular(wp-rp) <= CAP',invariant_basis='Reset sets equal pointers; serialized completed reads only when nonempty and completed writes only when not full preserve the bound',original_arithmetic_status_unchanged=True,request_latency_unchanged=True,default_parameter_behavior_preserved=True,widths=result,decision_sha256=matrix.hexdigest(),source_sha256=sha(root/source),selected_source_sha256=selected,model_sha256=sha(root/model),tool_sha256=sha(Path(__file__)))
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('RING POINTER DOMAIN '+('PASS'if r['accepted']else'FAILED '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
