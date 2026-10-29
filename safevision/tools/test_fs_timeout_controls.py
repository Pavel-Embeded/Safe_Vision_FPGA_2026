
import argparse,concurrent.futures,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE='safevision/rtl/storage/v3_file_streamer_compact_ctx.v'
TOP='tb_v3_fs_timeout_pipeline'
CASES=(('predicate_stuck_zero', 'else timeout_last_q<=last_file_byte;', "else timeout_last_q<=1'b0;"), ('predicate_stuck_one', 'else timeout_last_q<=last_file_byte;', "else timeout_last_q<=1'b1;"))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
 def run(case):
  name,before,after=case;folder=a.output/name;folder.mkdir();row=dict(name=name,target=SOURCE,before=before,after=after,suite='fs_timeout_pipeline',top=TOP,accepted=False)
  try:
   original=ROOT/SOURCE;text=original.read_text('utf-8-sig')
   if text.count(before)!=1:raise ValueError('mutant anchor differs')
   mutant=folder/'mutant.v';mutant.write_text(text.replace(before,after),encoding='utf-8',newline='\n')
   with(folder/'console.log').open('w',encoding='utf-8')as log:
    q=subprocess.run([sys.executable,'-B',str(ROOT/'safevision/tools/run_v3_sim_flexible.py'),'--suite','fs_timeout_pipeline','--run-dir',str(folder/'native'),'--override-source',SOURCE+'='+str(mutant)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=500)
   sim=folder/'native'/TOP/'sim.log';raw=sim.read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]
   actual=re.findall(r'\bdata_errors=(\d+)',raw);driver=re.findall(r'\bdriver_errors=(\d+)',raw)
   if not(q.returncode==1 and'$finish called'in raw and'PASS '+TOP in raw and'[FAIL] full file-streamer public interface differs'in raw and counts and any(counts)):raise ValueError('no complete semantic comparison failure')
   if len(actual)!=1 or int(actual[0])<=0 or driver!=['0']:raise ValueError('only driver timeout detected')
   if re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)or'[SKIP]'in raw:raise ValueError('mutant crashed or skipped')
   row.update(accepted=True,process_exit=q.returncode,normal_completion=True,error_counts=counts,actual_data_comparison_errors=int(actual[0]),driver_errors=0,original_sha256=sha(original),mutated_sha256=sha(mutant),sim_sha256=sha(sim))
  except Exception as exc:row['error']=str(exc)
  (folder/'result.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8');print(name+': '+('DETECTED'if row['accepted']else'FAILED '+row['error']),flush=True);return row
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:rows=list(pool.map(run,CASES))
 accepted=all(row['accepted']for row in rows);(a.output/'summary.json').write_text(json.dumps(dict(accepted=accepted,cases=rows),indent=2)+'\n',encoding='utf-8');return 0 if accepted else 1
if __name__=='__main__':raise SystemExit(main())
