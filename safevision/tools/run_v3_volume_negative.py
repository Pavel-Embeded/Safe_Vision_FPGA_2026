from pathlib import Path
import json,re,hashlib,subprocess,sys,argparse
repo=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
ap=argparse.ArgumentParser();ap.add_argument('--run-dir',required=True);a=ap.parse_args();out=Path(a.run_dir).resolve();out.mkdir(parents=True,exist_ok=True)
if not str(out).isascii():raise ValueError('ASCII run directory required')
source=repo/'safevision/rtl/audio/v3_audio_volume.v';original=sha(source);runner_sha=sha(Path(__file__))
s=source.read_text(encoding='utf-8');anchor="trial-8'd100"
if s.count(anchor)!=1:raise RuntimeError('division mutation anchor count changed')
mutant=out/'wrong_subtraction.v';mutant.write_text(s.replace(anchor,"trial-8'd99"),encoding='utf-8');mutant_sha=sha(mutant)
cmd=[sys.executable,str(repo/'safevision/tools/run_v3_sim.py'),'--suite','volume_serial','--run-dir',str(out/'xsim'),'--override-source','safevision/rtl/audio/v3_audio_volume.v='+str(mutant)]
with (out/'runner.log').open('w',encoding='utf-8') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=180)
run=out/'xsim/tb_v3_volume_serial';text=(run/'sim.log').read_text(encoding='utf-8',errors='replace');child=json.loads((out/'xsim/results.json').read_text())
errors=[int(x) for x in re.findall(r'errors=(\d+)',text)];finished='$finish called' in text and 'PASS tb_v3_volume_serial errors=' in text
bad=bool(re.search(r'(?im)^\s*(Fatal:|FATAL|ERROR:)',text));before=json.loads((run/'sources.sha256.json').read_text())
after={key:sha(mutant if key=='safevision/rtl/audio/v3_audio_volume.v' else repo/key) for key in before}
unchanged=before==after and sha(source)==original and sha(mutant)==mutant_sha and sha(Path(__file__))==runner_sha
stages=child['results'][0].get('error','').startswith('missing completion/checks or nonzero error:')
detected=p.returncode==1 and stages and finished and not bad and bool(errors) and errors[-1]>0 and '[FAIL] left exact signed /100' in text and unchanged
record={'mutation':'wrong_restoring_subtraction99','detected':bool(detected),'normal_completion':finished and not bad,'native_stages_completed':stages,'tool_failure':bad,'error_counts':errors,'original_sha256':original,'mutant_sha256':mutant_sha,'raw_log_sha256':sha(run/'sim.log'),'source_before_sha256':before,'source_after_sha256':after,'source_unchanged':before==after}
report={'complete':bool(detected),'cases':[record],'originals_preserved':unchanged,'runner_sha256':runner_sha,'hardware_verified':False};(out/'negative_controls.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps({key:value for key,value in record.items() if not key.startswith('source_')}),flush=True)
raise SystemExit(0 if detected else 1)
