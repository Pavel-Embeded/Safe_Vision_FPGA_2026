
import argparse,concurrent.futures,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
T='safevision/rtl/video/v3_scrolling_ticker.v'
A='safevision/rtl/video/v3_audio_spectrum.v'
CASES=(
 ('font_high_address_lost',A,"SHARED_PACKED_FONT?font_index_hi:1'b0","1'b0",'lossless_shared32','tb_v3_lossless_shared32'),
 ('font_highest_bit_lost',T,'font_word9[packed_bit2]',"(packed_bit2==7?1'b0:font_word9[packed_bit2])",'lossless_shared32','tb_v3_lossless_shared32'),
 ('font_quotient_corrupt',T,'packed_quotient=packed_linear[7:3]','packed_quotient=packed_linear[7:3]+1\'b1','lossless_shared32','tb_v3_lossless_shared32'),
 ('font_latency_extra_clock',T,'PIXEL_LATENCY-(PACKED_EXTERNAL?4:3)','PIXEL_LATENCY-(PACKED_EXTERNAL?3:3)','lossless_shared32','tb_v3_lossless_shared32'),
 ('font_publication_not_held',A,'BAND_WRITE:if(!font_access)begin','BAND_WRITE:if(1\'b1)begin','lossless_shared32_fft','tb_v3_lossless_shared32_fft'),
)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--case',action='append');ap.add_argument('--workers',type=int,default=2);a=ap.parse_args()
 selected=[c for c in CASES if not a.case or c[0]in a.case]
 if not selected or a.case and set(a.case)!={c[0]for c in selected}:raise ValueError('unknown control selection')
 a.output.mkdir(parents=True,exist_ok=False)
 def job(case):
  name,target,before,after,suite,top=case;folder=a.output/name;folder.mkdir();row=dict(name=name,target=target,before=before,after=after,suite=suite,top=top,accepted=False)
  try:
   source=ROOT/target;text=source.read_text('utf-8-sig')
   if text.count(before)!=1:raise ValueError('expected exactly one mutation anchor')
   mutant=folder/'mutant.v';mutant.write_text(text.replace(before,after),'utf-8',newline='\n')
   with(folder/'console.log').open('w',encoding='utf-8')as log:
    p=subprocess.run([sys.executable,'-B',str(ROOT/'safevision/tools/run_v3_sim_flexible.py'),'--suite',suite,'--top',top,'--run-dir',str(folder/'native'),'--override-source',target+'='+str(mutant)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=1900)
   sim=folder/'native'/top/'sim.log';raw=sim.read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',raw)]
   if not(p.returncode==1 and '$finish called'in raw and'PASS '+top in raw and'[FAIL]'in raw and counts and any(counts)):raise ValueError('no normally completed semantic detection')
   if re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',raw)or'[SKIP]'in raw:raise ValueError('control crashed or skipped')
   row.update(accepted=True,process_exit=p.returncode,normal_completion=True,error_counts=counts,original_sha256=sha(source),mutated_sha256=sha(mutant),sim_sha256=sha(sim))
  except Exception as exc:row['error']=str(exc)
  (folder/'result.json').write_text(json.dumps(row,indent=2)+'\n','utf-8');print(name+': '+('DETECTED'if row['accepted']else'FAILED '+row['error']),flush=True);return row
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers)as pool:rows=list(pool.map(job,selected))
 accepted=all(r['accepted']for r in rows)
 (a.output/'summary.json').write_text(json.dumps(dict(accepted=accepted,cases=rows),indent=2)+'\n','utf-8')
 return 0 if accepted else 1
if __name__=='__main__':raise SystemExit(main())
