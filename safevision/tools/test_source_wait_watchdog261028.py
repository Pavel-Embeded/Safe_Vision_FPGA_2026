"""Reproduce four normally finishing source-wait semantic controls with XSim."""
import argparse,concurrent.futures,hashlib,json,re,subprocess,sys
from pathlib import Path

WRITER='safevision/rtl/memory/frame_writer.v'
SINK='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v'
CASES=[
 ('pending_write_hint_unprotected',WRITER,'SOURCE_PROGRESS_AWARE && source_progress && !wr_pending && !din_valid','SOURCE_PROGRESS_AWARE && source_progress && !din_valid','source_wait_writer261028','tb_v3_source_wait_writer'),
 ('legacy_hint_enabled',WRITER,'SOURCE_PROGRESS_AWARE && source_progress && !wr_pending && !din_valid',"1'b1 && source_progress && !wr_pending && !din_valid",'source_wait_legacy261028','tb_v3_source_wait_legacy'),
 ('deadline_priority_lost',SINK,'SOURCE_PROGRESS_AWARE && (source_wait_credit || br_px_cnt!=px_d)',"1'b0 && (source_wait_credit || br_px_cnt!=px_d)",'source_wait_watchdog261028','tb_v3_source_wait_watchdog'),
 ('physical_drain_guard_lost',SINK,'state_o==S_WRITE && fa_sync[2] && write_drained &&','state_o==S_WRITE && fa_sync[2] &&','source_wait_watchdog261028','tb_v3_source_wait_watchdog'),
]

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text('utf-8-sig'))

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--repo',type=Path,required=True)
 parser.add_argument('--output',type=Path,required=True)
 parser.add_argument('--workers',type=int,default=2,choices=(1,2,3,4))
 parser.add_argument('--xsim-bin',type=Path)
 args=parser.parse_args();root=args.repo.resolve();out=args.output.resolve()
 if not str(out).isascii():raise ValueError('XSim output must use an ASCII path')
 out.mkdir(parents=True,exist_ok=False)
 sys.path.insert(0,str(root/'safevision/tools'))
 from check_v3_sim_graph import check as graph
 runner=root/'safevision/tools/run_v3_sim_flexible.py'
 def run(case):
  name,target,before,after,suite,top=case;folder=out/name;folder.mkdir()
  record=dict(name=name,target=target,before=before,after=after,suite=suite,top=top,accepted=False)
  try:
   source=(root/target).resolve()
   assert source.is_relative_to(root),'target escaped repository'
   original_sha=sha(source);text=source.read_text('utf-8-sig')
   assert text.count(before)==1,'semantic patch occurrence differs'
   mutant=folder/'mutant.v';mutant.write_text(text.replace(before,after),'utf-8',newline='\n')
   record.update(original_sha256=original_sha,mutated_sha256=sha(mutant))
   command=[sys.executable,'-B',str(runner),'--suite',suite,'--run-dir',str(folder/'native'),'--override-source',target+'='+str(mutant)]
   if args.xsim_bin:command+=['--xsim-bin',str(args.xsim_bin.resolve())]
   with(folder/'console.log').open('w',encoding='utf-8')as log:
    code=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=1200).returncode
   native=folder/'native'/top;sim=native/'sim.log';raw=sim.read_text('utf-8',errors='replace')
   counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]
   assert code==1 and '$finish called'in raw and 'PASS '+top in raw and '[FAIL]'in raw and counts and any(counts),'not a normally finishing semantic detection'
   assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)and'[SKIP]'not in raw,'crash or skipped check'
   assert sha(source)==original_sha,'original source changed while running'
   assert read(native/'sources.sha256.json')==read(native/'sources.after.sha256.json'),'captured execution inputs changed'
   compiler=graph(root,native,dict(suite=suite,top=top),record)
   record.update(accepted=True,process_exit=code,normal_completion=True,error_counts=counts,sim_sha256=sha(sim),compiler=compiler)
  except Exception as exc:record['error']=type(exc).__name__+': '+str(exc)
  (folder/'result.json').write_text(json.dumps(record,indent=2)+'\n','utf-8')
  print(name+': '+('PASS'if record['accepted']else'FAIL '+record['error']),flush=True)
  return record
 with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers)as pool:rows=list(pool.map(run,CASES))
 accepted=all(row['accepted']for row in rows)
 (out/'summary.json').write_text(json.dumps(dict(accepted=accepted,cases=rows,driver_sha256=sha(Path(__file__)),runner_sha256=sha(runner)),indent=2)+'\n','utf-8')
 print('SOURCE WAIT CONTROLS '+('PASS'if accepted else'FAIL'),flush=True)
 return 0 if accepted else 1

if __name__=='__main__':raise SystemExit(main())
