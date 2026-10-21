"""Adversarial gate checks; expected rejection never becomes feature approval."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,copy,hashlib,json,shutil,subprocess,sys
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--source-repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
S=a.repo.resolve();R=a.source_repo.resolve();O=a.output.resolve();O.mkdir();E=S/'evidence/v3'/('four_features_gate_'+O.name);E.mkdir()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'));sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
complete=read(S/'evidence/v3/four_features_261020/acceptance.json');assert complete['complete'];matrix=read(S/complete['matrix']);assert len(complete['positive_tests'])==288
index=copy.deepcopy(complete);index['complete']=False;index['positive_tests']=[r for r in index['positive_tests']if r['top']!='tb_v3_max_card241'];assert len(index['positive_tests'])==287
def save(name,j):
 p=E/(name+'.json');p.write_text(json.dumps(j,indent=2)+'\n');return p.relative_to(S).as_posix()
partial=save('partial_fixture',index)
jobs=[dict(name='healthy_partial',manifest=partial,inspect=True,expected_exit=2,expected_error=None),dict(name='incomplete_default',manifest=partial,inspect=False,expected_exit=1,expected_error='positive producer has not completed')]
j=copy.deepcopy(index);j['complete']=True;jobs.append(dict(name='forged_complete',manifest=save('forged_complete',j),inspect=False,expected_exit=1,expected_error='missing required positive evidence'))
j=copy.deepcopy(index);r=next(x for x in j['positive_tests']if x['top']=='tb_v3_ui_timebase395');dest=E/'missing_finish';shutil.copytree(S/r['evidence'],dest);p=dest/'sim.log';text=p.read_text();assert '$finish called'in text;p.write_text(text.replace('$finish called','FINISH_REMOVED'),encoding='utf-8');r['evidence']=dest.relative_to(S).as_posix();jobs.append(dict(name='missing_finish',manifest=save('missing_finish',j),inspect=True,expected_exit=1,expected_error='tb_v3_ui_timebase395'))
j=copy.deepcopy(index);r=next(x for x in j['negative_controls']if x['mutation']=='default_auto_disabled');dest=E/'wrong_exit';shutil.copytree(S/r['evidence'],dest);p=dest/'case.json';c=read(p);assert c['process_exit']==1;c['process_exit']=0;p.write_text(json.dumps(c,indent=2)+'\n');r['evidence']=dest.relative_to(S).as_posix();jobs.append(dict(name='wrong_exit',manifest=save('wrong_exit',j),inspect=True,expected_exit=1,expected_error='missing or inconsistent captured runner exit'))
j=copy.deepcopy(index);m=copy.deepcopy(matrix);name=next(iter(m['frozen_reference_sha256']));h=m['frozen_reference_sha256'][name];m['frozen_reference_sha256'][name]=('0'if h[0]!='0'else'1')+h[1:];j['matrix']=save('wrong_reference_matrix',m);jobs.append(dict(name='wrong_reference',manifest=save('wrong_reference',j),inspect=True,expected_exit=1,expected_error='independent reference changed'))
def run(job):
 d=O/job['name'];d.mkdir();report=d/'result.json';cmd=[sys.executable,'-X','utf8','-B',str(S/'safevision/tools/audit_v3_four_features.py'),'--repo',str(S),'--source-repo',str(R),'--manifest',job['manifest'],'--output',str(report)]
 if job['inspect']:cmd+=['--inspect-incomplete']
 with(d/'runner.log').open('wb')as f:rc=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=1800).returncode
 j=read(report);okay=rc==job['expected_exit']and j['accepted']is False and j['release_ready']is False
 if job['expected_error']:okay=okay and job['expected_error']in j.get('error','')
 else:okay=okay and j['positive_unique_tops']==287 and j['strict_normal_ending_mutants']==202 and j['missing_positive']==['tb_v3_max_card241']
 r=dict(**job,accepted=bool(okay),process_exit=rc,actual_error=j.get('error'),native_report_sha256=sha(report),functional_approval=False);(d/'completion.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r),flush=True);return r
with ThreadPoolExecutor(max_workers=3)as pool:results=list(pool.map(run,jobs))
# The real finalizer must also reject the incomplete producer before Git/STA
# or bitgen, and leave no pending or named bitstream in its output directory.
for mode_args,label in (([],'both'),(['--engineering-base-only'],'base')):
 d=O/('finalizer_incomplete_'+label);cmd=[sys.executable,'-X','utf8','-B',str(S/'safevision/tools/finalize_v3_four_features.py'),'--repo',str(S),'--native-run',str(O/'unused_native'),'--functional-manifest',partial,'--output',str(d),'--check-only']+mode_args
 rc=subprocess.run(cmd,capture_output=True).returncode;j=read(d/'release.index.json');r=dict(name='finalizer_incomplete_'+label,accepted=rc==1 and not j['accepted']and 'positive producer has not completed'in j['error']and not list(d.glob('*.bit'))and j['requested_modes']==(['base']if mode_args else['base','hd']),process_exit=rc,functional_approval=False);results.append(r)
summary=dict(accepted=all(r['accepted']for r in results),gate_behavior_tests=results,functional_approval=False,bitgen_performed=False,helper_sha256={p.name:sha(p)for p in (Path(__file__),S/'safevision/tools/finalize_v3_four_features.py',S/'safevision/tools/audit_v3_four_features.py')});(O/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');assert summary['accepted']
