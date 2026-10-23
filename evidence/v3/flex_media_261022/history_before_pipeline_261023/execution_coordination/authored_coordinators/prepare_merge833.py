from pathlib import Path
W=Path('work');v=(W/'merge_diag831.py').read_text()
v=v.replace("fresh=read(O/'complete.json');assert fresh['complete']and len(fresh['records'])==7 and fresh['physical205_unchanged']","fresh=read(O/'complete.json');assert fresh['complete']and len(fresh['records'])==7 and fresh['physical205_unchanged'];counter=read(B/'qualification832/complete.json');assert counter['complete']and counter['production_assertions_unchanged'];fresh['records'].append(counter['record'])")
anchor="for row in patch['patches']:";assert v.count(anchor)==1
v=v.replace(anchor,"""M=R/'safevision/build/qualification/four_features_261020.json';(H/'matrix.before.json').write_bytes(M.read_bytes());matrix=read(M)
old=next(r for r in matrix['negative']if r['mutation']=='frame_counter_one_bit_short');assert old==counter['original_definition']
matrix['negative']=[counter['revised_definition']if r['mutation']=='frame_counter_one_bit_short'else r for r in matrix['negative']];M.write_bytes((json.dumps(matrix,indent=2)+'\\n').encode())
for row in patch['patches']:""")
anchor="plan=read(Q/'plan.json');definitions={(r['kind'],r['name']):r['row']for r in plan['records']};freshmap=";assert v.count(anchor)==1
v=v.replace(anchor,"plan=read(Q/'plan.json');definitions={(r['kind'],r['name']):r['row']for r in plan['records']};definitions[('negative','frame_counter_one_bit_short')]=counter['revised_definition'];freshmap=")
anchor="assert cohort['complete'],'Other current-source failures remain'";assert v.count(anchor)==1
v=v.replace(anchor,"""cohort['counter_fault_requalification']=dict(complete=True,normal_semantic_detection=True,negative=1,production_assertions_unchanged=True,cohort=str(B/'qualification832'))
cohort['accepted_fresh_native_records']=215;cohort['actual_main_native_attempts_including_retries']=223;cohort['failed_native_attempts_preserved']=8
assert cohort['complete'],'Other current-source failures remain'""")
v=v.replace('7 former failed native attempts retained.','8 former failed native attempts retained; counter public oracle normal detection qualified.')
(W/'merge_final833.py').write_bytes(v.encode());print('Prepared combined diagnostic+coherent-counter qualification merge.')
