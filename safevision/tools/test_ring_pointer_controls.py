
import argparse,concurrent.futures,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
R='safevision/rtl/audio/v3_pcm_ring.v'
T='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
CASES=(
 ('ring_empty_inverted',R,'DIRECT_POINTER_COMPARE?!pointer_empty[active]','DIRECT_POINTER_COMPARE?pointer_empty[active]','ring_pointer_trace','tb_v3_ring_pointer_trace'),
 ('ring_full_wrong_phase',R,'{~rp[g][PTR_W],rp[g][PTR_W-1:0]}','{rp[g][PTR_W],rp[g][PTR_W-1:0]}','ring_pointer_trace','tb_v3_ring_pointer_trace'),
 ('ring_empty_ignores_wrap',R,'pointer_empty[g]=(wp[g]==rp[g]);','pointer_empty[g]=(wp[g][PTR_W-1:0]==rp[g][PTR_W-1:0]);','ring_pointer_trace','tb_v3_ring_pointer_trace'),
 ('ring_status_bit_changed',R,"assign levels[g*16+:16]={{(15-PTR_W){1'b0}},count[g]};","assign levels[g*16+:16]={{(15-PTR_W){1'b0}},count[g]}^16'h0001;",'ring_pointer_trace','tb_v3_ring_pointer_trace'),
 ('ring_production_mode_disabled',T,'v3_audio_system #(.DIRECT_RING_COMPARE(TICKER_ENABLE),','v3_audio_system #(.DIRECT_RING_COMPARE(0),','ticker_board261028','tb_v3_ticker_board'),
)
CASES+=(
 ('ring_occupancy_sign_reversed',R,"value<=value+{{PTR_W{reading}},1'b1};","value<=value+{{PTR_W{!reading}},1'b1};",'ring_pointer_trace','tb_v3_ring_pointer_trace'),
 ('ring_occupancy_owner_leaks',R,'else if(owner==slot_index && (take_read || finish_write))','else if(take_read || finish_write)','ring_pointer_trace','tb_v3_ring_pointer_trace'),
 ('ring_occupancy_read_ignored',R,'else if(owner==slot_index && (take_read || finish_write))','else if(owner==slot_index && finish_write)','ring_pointer_trace','tb_v3_ring_pointer_trace'),
)

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--case',action='append');p.add_argument('--workers',type=int,default=2);a=p.parse_args()
 selected=[c for c in CASES if not a.case or c[0]in a.case]
 if not selected or a.case and set(a.case)!={c[0]for c in selected}:raise ValueError('unknown selected control')
 a.output.mkdir(parents=True,exist_ok=False)
 def run(case):
  name,target,before,after,suite,top=case;folder=a.output/name;folder.mkdir();row=dict(name=name,target=target,before=before,after=after,suite=suite,top=top,accepted=False)
  try:
   text=(ROOT/target).read_text('utf-8-sig')
   if text.count(before)!=1:raise ValueError('mutation anchor differs')
   mutant=folder/'mutant.v';mutant.write_text(text.replace(before,after),'utf-8',newline='\n')
   with(folder/'console.log').open('w',encoding='utf-8')as log:
    q=subprocess.run([sys.executable,'-B',str(ROOT/'safevision/tools/run_v3_sim_flexible.py'),'--suite',suite,'--run-dir',str(folder/'native'),'--override-source',target+'='+str(mutant)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=700)
   sim=folder/'native'/top/'sim.log';raw=sim.read_text('utf-8',errors='replace');counts=[int(v)for v in re.findall(r'errors\s*=\s*(\d+)',raw)]
   if not(q.returncode==1 and'$finish called'in raw and'PASS '+top in raw and'[FAIL]'in raw and counts and any(counts)):raise ValueError('no normal semantic comparison failure')
   if re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)or'[SKIP]'in raw:raise ValueError('control crashed or skipped')
   if suite=='ring_pointer_trace':
    actual=re.findall(r'\bdata_errors=(\d+)',raw)
    if len(actual)!=1 or int(actual[0])<=0 or not re.search(r'\[FAIL\].*(?:every public output|occupancies|prefetch threshold|independent PCM)',raw):raise ValueError('driver stall alone is not a semantic detection')
    row['actual_data_comparison_errors']=int(actual[0])
   elif'[FAIL] production selects direct full/empty pointer scheduling'not in raw:raise ValueError('production mode selection detector absent')
   row.update(accepted=True,process_exit=q.returncode,normal_completion=True,error_counts=counts,original_sha256=sha(ROOT/target),mutated_sha256=sha(mutant),sim_sha256=sha(sim))
  except Exception as exc:row['error']=str(exc)
  (folder/'result.json').write_text(json.dumps(row,indent=2)+'\n','utf-8');print(name+': '+('DETECTED'if row['accepted']else'FAILED '+row['error']),flush=True);return row
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers)as pool:rows=list(pool.map(run,selected))
 accepted=all(r['accepted']for r in rows);(a.output/'summary.json').write_text(json.dumps(dict(accepted=accepted,cases=rows),indent=2)+'\n','utf-8');return 0 if accepted else 1
if __name__=='__main__':raise SystemExit(main())
