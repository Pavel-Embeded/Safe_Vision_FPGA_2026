from pathlib import Path
import json,sys
B=Path('D:/Codex/svflex537');R=B/'candidate803';I=R/'evidence/v3/four_features_261020/acceptance.json';raw=I.read_bytes();index=json.loads(raw);assert not index['complete']and json.loads((B/'qualification811/complete.json').read_text())['complete']
H=R/'evidence/v3/flex_media_261022/history_before_pipeline_261023/execution_coordination';assert(H/'preserved.inputs.json').is_file()and json.loads((H/'requirements_counter_selftest836.json').read_text())['accepted']
sys.path.insert(0,str(R/'safevision/tools'));from audit_v3_four_features import audit
try:
 r=audit(R,'evidence/v3/four_features_261020/acceptance.json',R,inspect_incomplete=True);assert not r['accepted']and not r['missing_positive']and r['positive_unique_tops']==303 and len(r['negative'])==221 and r['physical_inputs']==205
 for n in ['flexible_media_auxiliary','compact_ingress_auxiliary','wav_pipeline_auxiliary','lba_control_clock_auxiliary','pipeline_auxiliary']:assert r[n]['accepted']
 (B/'functional828.preflight.json').write_text(json.dumps(r,indent=2)+'\n');index['complete']=True;I.write_bytes((json.dumps(index,indent=2)+'\n').encode());r=audit(R,'evidence/v3/four_features_261020/acceptance.json',R);assert r['accepted'];(B/'functional818.audit.json').write_text(json.dumps(r,indent=2)+'\n')
except BaseException:I.write_bytes(raw);raise
print('Full current803 functional gate PASS:303 positives221 normally detecting mutants; all mandatory aux gates PASS.',flush=True)
