"""Require public row-CRC mismatches for both direct-index implementations."""
import argparse,concurrent.futures,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CASES=(
 ('slot_carry_lost',"direct_slot_sum={1'b0,lookup_slot_index}+{2'b0,lookup_row_index[9]};","direct_slot_sum={1'b0,lookup_slot_index};"),
 ('row_index_shifted',"query_row=USE_DIRECT?{1'b0,lookup_row_index[8:0]}:legacy_query_row;","query_row=USE_DIRECT?{lookup_row_index[8:0],1'b0}:legacy_query_row;"))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8',newline='\n')
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
 for mode in('base','hd'):(a.output/mode).mkdir()
 def run(job):
  mode,case=job;name,before,after=case;variant='memory'if mode=='base'else'hd'
  target=f'safevision/rtl/{variant}/v3_row_integrity.v';suite='direct_row_'+mode+'113';top='tb_v3_direct_row_'+mode
  folder=a.output/mode/name;folder.mkdir();row=dict(name=name,target=target,before=before,after=after,suite=suite,top=top,accepted=False)
  try:
   source=ROOT/target;text=source.read_text('utf-8-sig');assert text.count(before)==1,'mutant anchor differs'
   mutant=folder/'mutant.v';mutant.write_text(text.replace(before,after),encoding='utf-8',newline='\n')
   with(folder/'console.log').open('w',encoding='utf-8')as log:
    q=subprocess.run([sys.executable,'-B',str(ROOT/'safevision/tools/run_v3_sim_flexible.py'),'--suite',suite,'--run-dir',str(folder/'native'),'--override-source',target+'='+str(mutant)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=800)
   sim=folder/'native'/top/'sim.log';raw=sim.read_text('utf-8');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]
   actual=re.findall(r'\bdata_errors=(\d+)',raw)
   assert q.returncode==1 and'$finish called'in raw and'PASS '+top in raw and'[FAIL] complete row-guard public interface differs'in raw
   assert len(actual)==1 and int(actual[0])>0 and re.findall(r'\bdriver_errors=(\d+)',raw)==['0']
   assert re.findall(r'\bqueries=(\d+)',raw)==['4096']and re.findall(r'\bverified_frames=(\d+)',raw)==['4']
   assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw
   row.update(accepted=True,process_exit=q.returncode,normal_completion=True,error_counts=counts,actual_data_comparison_errors=int(actual[0]),driver_errors=0,original_sha256=sha(source),mutated_sha256=sha(mutant),sim_sha256=sha(sim))
  except Exception as exc:row['error']=str(exc)
  save(folder/'result.json',row);print(mode+'/'+name+': '+('DETECTED'if row['accepted']else'FAILED '+row['error']),flush=True);return mode,row
 jobs=[(mode,case)for mode in('base','hd')for case in CASES]
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:rows=list(pool.map(run,jobs))
 for mode in('base','hd'):
  cases=[row for m,row in rows if m==mode];save(a.output/mode/'summary.json',dict(accepted=all(row['accepted']for row in cases),cases=cases))
 accepted=all(row['accepted']for mode,row in rows);save(a.output/'summary.json',dict(accepted=accepted,cases=[dict(profile=mode,**row)for mode,row in rows]));return 0 if accepted else 1
if __name__=='__main__':raise SystemExit(main())
