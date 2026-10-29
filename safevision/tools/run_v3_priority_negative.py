
from pathlib import Path
import argparse,json,hashlib,subprocess,re,sys
repo=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--run-dir',required=True);args=ap.parse_args();out=Path(args.run_dir).resolve();out.mkdir(parents=True,exist_ok=True)
if not str(out).isascii():raise ValueError('ASCII run directory required')
runner_sha=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
candidate=repo/'safevision/rtl/audio/v3_audio_priority_serial.v';text=candidate.read_text(encoding='utf-8');original=hashlib.sha256(candidate.read_bytes()).hexdigest();records=[]
for name,old,new,count in [('erase_fraction',"$signed({19'd0,product[15:8]})","27'd0",2),('erase_negative_sign',"$signed({delta_l[24],delta_l[24:8]})","$signed({1'b0,delta_l[24:8]})",1)]:
 assert text.count(old)==count
 folder=out/name;folder.mkdir(exist_ok=True);mutant=folder/'priority_bundle.v';mutant.write_text(text.replace(old,new),encoding='utf-8')
 cmd=[sys.executable,str(repo/'safevision/tools/run_v3_sim.py'),'--suite','priority_serial','--top','tb_v3_priority_serial','--run-dir',str(folder/'simulation'),'--override-source','safevision/rtl/audio/v3_audio_priority_serial.v='+str(mutant)]
 with (folder/'runner.log').open('w') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=120)
 child=json.loads((folder/'simulation/results.json').read_text());run=folder/'simulation/tb_v3_priority_serial';log=(run/'sim.log').read_text(errors='replace')
 errors=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',log)]
 before=json.loads((run/'sources.sha256.json').read_text());after={k:hashlib.sha256((mutant if k=='safevision/rtl/audio/v3_audio_priority_serial.v' else repo/k).read_bytes()).hexdigest() for k in before}
 detected=p.returncode==1 and '$finish called' in log and bool(re.search(r'PASS tb_v3_priority_serial errors=',log)) and '[FAIL PRIORITY_SERIAL] two full PCM24 channels' in log and any(errors) and before==after and child['results'][0].get('error','').startswith('missing completion/checks or nonzero error:') and not re.search(r'(?im)^\s*(Fatal:|FATAL|ERROR:)',log)
 rec={'mutation':name,'detected':bool(detected),'normal_completion':'$finish called' in log,'error_counts':errors,'mutant_sha256':hashlib.sha256(mutant.read_bytes()).hexdigest(),'source_unchanged':before==after,'raw_log_sha256':hashlib.sha256((run/'sim.log').read_bytes()).hexdigest(),'source_before_sha256':before,'source_after_sha256':after};records.append(rec);print(json.dumps(rec),flush=True)
 report={'complete':len(records)==2 and all(x['detected'] for x in records) and hashlib.sha256(candidate.read_bytes()).hexdigest()==original and hashlib.sha256(Path(__file__).read_bytes()).hexdigest()==runner_sha,'cases':records,'candidate_preserved':hashlib.sha256(candidate.read_bytes()).hexdigest()==original,'candidate_sha256':original,'runner_sha256':runner_sha,'runner_unchanged':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()==runner_sha,'hardware_verified':False};(out/'negative_controls.json').write_text(json.dumps(report,indent=2))

raise SystemExit(0 if report["complete"] else 1)
