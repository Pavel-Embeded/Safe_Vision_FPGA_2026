"""Review exactly one coherent counter-fault extension; retain the original205 digest."""
from pathlib import Path
import json,hashlib,copy,sys,shutil
B=Path('D:/Codex/svflex537');R=B/'candidate803';H=R/'evidence/v3/flex_media_261022/history_before_pipeline_261023/execution_coordination';P=R/'safevision/tools/audit_v3_flexible_media537.py';old=P.read_bytes();backup=H/'auditors_before/audit_v3_flexible_media537.py';backup.parent.mkdir(parents=True,exist_ok=True);assert not backup.exists();backup.write_bytes(old)
v=old.decode();anchor=" pos_digest=definition_hash(baseline_pos,'top');neg_digest=definition_hash(baseline_neg,'mutation')";assert v.count(anchor)==1
replacement=''' # The counter-width fault still shortens SOURCE_W by exactly one bit.
 # Its redundant zero flag must describe the same faulty wrapped counter,
 # otherwise a new invariant aborts before the independent public oracle.
 # Accept only this exact pair; canonicalize to the reviewed historical
 # fault for the original205 hash. Main audit still verifies BOTH compiled
 # patches, all source bytes, normal finish and actual nonzero HDL errors.
 actual_neg_digest=definition_hash(baseline_neg,'mutation')
 counter_old=_mutation('frame_counter_one_bit_short','safevision/rtl/memory/v3_row_integrity.v','v3','tb_v3_row_integrity','SOURCE_W=$clog2(FRAME_WORDS+1)','SOURCE_W=$clog2(FRAME_WORDS+1)-1')
 counter_new=copy.deepcopy(counter_old)
 counter_new['patch'].append(dict(before="source_count<=source_words+1'b1;source_first<=0;",after="source_count<=source_words+1'b1;source_first<=(source_words[SOURCE_W-1:0]=={SOURCE_W{1'b1}});"))
 counter_row=neg['frame_counter_one_bit_short'];counter_model=None
 counter_claim=index.get('pipeline_requalification',{}).get('counter_fault_requalification',{})
 if _normalized_patch(counter_row)==counter_new:
  require(counter_claim.get('complete')and counter_claim.get('normal_semantic_detection')and counter_claim.get('production_assertions_unchanged'),'coherent counter fault lacks mandatory current native proof')
  rtl=(root/counter_old['target']).read_text(encoding='utf-8-sig')
  require(rtl.count(counter_old['patch'][0]['before'])==1 and rtl.count(counter_new['patch'][1]['before'])==1,'counter production anchors changed')
  require(rtl.count('if(source_first !== (source_words==0))$fatal(1,"unary source position invariant violated");')==1,'counter invariant was removed or weakened')
  baseline_neg=[counter_old if r['mutation']==counter_old['mutation']else r for r in baseline_neg]
  counter_model=dict(reviewed_exact_extension=True,original=counter_old,current=counter_new,production_assertions_unchanged=True,normal_native_detection_required_by_parent=True)
 else:
  require(not counter_claim.get('complete'),'qualified coherent counter fault definition missing or changed')
 pos_digest=definition_hash(baseline_pos,'top');neg_digest=definition_hash(baseline_neg,'mutation')'''
v=v.replace(anchor,replacement);anchor="base_negative_definition_sha256=neg_digest,new_positive_tops=";assert v.count(anchor)==1;v=v.replace(anchor,"base_negative_definition_sha256=neg_digest,actual_base_negative_definition_sha256=actual_neg_digest,reviewed_counter_fault_model=counter_model,new_positive_tops=")
v=v.replace('# The sole previously reviewed adjustment is the complete FLEX width guard in\n# bmp_width_guard_bypassed, not a weakened prefix of that expression.','# The existing digest includes the complete FLEX width guard. The exact\n# coherent counter-zero-flag extension is separately checked and documented\n# below; all205 original fault identities remain mandatory.')
P.write_bytes(v.encode());sys.path.insert(0,str(R/'safevision/tools'));from audit_v3_flexible_media537 import requirements
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'));index=read(R/'evidence/v3/four_features_261020/acceptance.json');matrix=read(R/index['matrix']);good=requirements(R,index,matrix);assert good['requirements_verified']and good['reviewed_counter_fault_model']['production_assertions_unchanged']
controls=[]
def reject(name,change):
 i=copy.deepcopy(index);m=copy.deepcopy(matrix);change(i,m)
 try:requirements(R,i,m)
 except (ValueError,KeyError,AssertionError)as e:controls.append(dict(name=name,rejected=True,error=str(e)))
 else:raise AssertionError('Changed semantic contract accepted: '+name)
def counter(m):return next(r for r in m['negative']if r['mutation']=='frame_counter_one_bit_short')
reject('width_patch_removed',lambda i,m:counter(m)['patch'].pop(0))
reject('zero_flag_wrong',lambda i,m:counter(m)['patch'][1].update(after="source_first<=1'b1;"))
reject('zero_flag_extension_removed',lambda i,m:counter(m)['patch'].pop())
reject('wrong_target',lambda i,m:counter(m).update(target='safevision/rtl/hd/v3_row_integrity.v'))
reject('nonunique_patch',lambda i,m:counter(m)['patch'][1].update(occurrences=2))
reject('current_proof_missing',lambda i,m:i['pipeline_requalification'].pop('counter_fault_requalification'))
reject('other_historical_fault_changed',lambda i,m:m['negative'][0]['patch'][0].update(after='unreviewed'))
reject('historical_positive_removed',lambda i,m:m['positive'].pop(0))
assert len(controls)==8 and requirements(R,index,matrix)['requirements_verified']
out=H/'requirements_counter_selftest836.json';out.write_bytes((json.dumps(dict(accepted=True,canonical_historical205_digest_unchanged=good['base_negative_definition_sha256'],actual_current205_digest=good['actual_base_negative_definition_sha256'],original_auditor_sha256=hashlib.sha256(old).hexdigest(),current_auditor_sha256=hashlib.sha256(P.read_bytes()).hexdigest(),exact_fault_model=good['reviewed_counter_fault_model'],negative_controls=controls,hardware_source_not_modified=True),indent=2)+'\n').encode());print('Exact coherent counter-fault contract accepted; all8 altered/missing semantic contracts rejected. Original205 digest retained.',flush=True)
