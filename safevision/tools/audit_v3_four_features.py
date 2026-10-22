"""Audit the complete four-feature evidence matrix; this never approves STA."""
from pathlib import Path
import argparse,ast,hashlib,json,re,subprocess,sys

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def within(root,name):
 p=(root/name).resolve()
 if not p.is_relative_to(root.resolve()):raise ValueError('path escaped root: '+str(name))
 return p

def git_bytes(repo,commit,names):
 names=sorted(names);p=subprocess.run(['git','-C',str(repo),'cat-file','--batch'],input=''.join(commit+':'+n+'\n'for n in names).encode(),capture_output=True)
 if p.returncode:raise ValueError('Git object read failed')
 out={};offset=0
 for n in names:
  end=p.stdout.index(b'\n',offset);header=p.stdout[offset:end].split();assert len(header)==3 and header[1]==b'blob',(n,header)
  size=int(header[2]);offset=end+1;out[n]=p.stdout[offset:offset+size];offset+=size;assert p.stdout[offset:offset+1]==b'\n';offset+=1
 assert offset==len(p.stdout)
 return out

def audit(root,manifest,repository,inspect_incomplete=False):
 if not __debug__:raise RuntimeError('assertions must remain enabled')
 sys.path.insert(0,str(root/'safevision/tools'))
 from audit_v3_raw_logs import audit_file
 from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 from v3_sources import snapshot,check_gui,build_parameters,native_parameters
 from run_v3_board import source_commit_binding
 index=read(within(root,manifest));assert index['schema']==1 and index['profile']=='four_features_261020'
 if not inspect_incomplete:assert index['complete'],'positive producer has not completed'
 matrix_path=within(root,index['matrix']);matrix=read(matrix_path);assert matrix['profile']==index['profile']
 assert matrix['source_build_commit']==index['source_build_commit']
 alias_extension=index.get('media_alias_extension_schema')==1
 expected_positive=290 if alias_extension else 288
 expected_negative=205 if alias_extension else 202
 expected_records=291 if alias_extension else 289
 expected_physical=198
 flexible_extension=index.get('flexible_media_extension_schema')==1
 if flexible_extension:
  assert alias_extension,'FLEX retains the original alias qualification'
  from audit_v3_flexible_media537 import requirements as flexible_requirements
  extension=flexible_requirements(root,index,matrix)
  expected_positive=extension['expected_positive'];expected_negative=extension['expected_negative']
  expected_records=extension['expected_records'];expected_physical=extension['expected_physical']
 assert len(matrix['positive'])==expected_positive and len(matrix['negative'])==expected_negative and matrix['positive_records_including_aliases']==expected_records
 assert len({r['top']for r in matrix['positive']})==expected_positive and len({r['mutation']for r in matrix['negative']})==expected_negative
 if alias_extension:
  assert {'tb_v3_directory_alias510','tb_v3_actual_directory510'}<=set(r['top']for r in matrix['positive'])
  assert {'media_alias_reject_three_digits','media_alias_retain_previous_high_nibble','media_alias_wrong_digit_order'}<=set(r['mutation']for r in matrix['negative'])
 hardware=snapshot(root);assert hardware==matrix['physical_source_sha256']and len(hardware)==expected_physical
 # Native identity hashes preserve actual bytes; Git additionally applies its
 # recorded text filters. Use the same explicit blob binding as the native
 # driver instead of mistaking a declared CRLF checkout for a source change.
 binding=source_commit_binding(root,repository,matrix['source_build_commit'],hardware);assert binding['verified'],binding['errors']
 legacy_ports=None
 if flexible_extension:
  from check_v3_legacy_ports537 import check as ordered_port_check
  legacy_ports=ordered_port_check(root,repository)
  assert legacy_ports['accepted']
 committed=git_bytes(repository,matrix['source_build_commit'],matrix['frozen_reference_sha256'])
 protected={matrix_path.relative_to(root).as_posix():sha(matrix_path),within(root,manifest).relative_to(root).as_posix():sha(within(root,manifest))}
 for n,h in matrix['frozen_reference_sha256'].items():
  assert sha(within(root,n))==h==hashlib.sha256(committed[n]).hexdigest(),'independent reference changed: '+n
  protected[n]=h
 # The four new public-interface oracles also recover their exact old RTL,
 # with the declared module-name change as the sole transformation.
 for stem in ('v3_uart_link_control_reference353','v3_uart_link_hd_reference353','sdram_adapter_base_reference385','sdram_adapter_hd_reference385'):
  meta=read(root/('safevision/verification/models/'+stem+'.freeze.json'));raw=(root/('safevision/verification/models/'+stem+'.sv')).read_bytes()
  assert hashlib.sha256(raw).hexdigest()==meta['reference_sha256']
  for old,new in meta['namespace_only']:raw=raw.replace(new.encode(),old.encode())
  original=within(root,meta['original_path']).read_bytes();assert raw==original and hashlib.sha256(original).hexdigest()==meta['original_sha256']
  historical=git_bytes(repository,meta['original_source_commit'],[meta['original_repository_path']]);assert historical[meta['original_repository_path']]==original
 expected={r['top']:r for r in matrix['positive']};actual={r['top']:r for r in index['positive_tests']};assert len(actual)==len(index['positive_tests'])and set(actual)<=set(expected)
 missing_positive=sorted(set(expected)-set(actual))
 if not inspect_incomplete:assert not missing_positive,('missing required positive evidence',missing_positive)
 records=[];positive_meta={}
 for top in sorted(actual):
  wanted=expected[top]
  row=actual[top];assert(row['suite'],row['legacy'])==(wanted['suite'],wanted['legacy'])
  folder=within(root,row['evidence']);meta=read(folder/'result.json');assert meta['top']==top and meta['suite']==row['suite']and not meta['source_overrides']and meta['accepted_native_runner']
  if row['legacy']:assert meta['legacy']
  else:assert meta['status']=='PASS'
  assert sha(folder/'result.json')==row['result_sha256'];count=sources(root,folder);g=graph(root,folder,meta)
  raw=audit_file(folder/'sim.log',not row['legacy']);assert raw['accepted'],(top,raw)
  positive_meta[top]=(folder,meta);records.append(dict(top=top,source_bindings=count,compiler_graph=g,raw_log_sha256=raw['sha256']))
  for p in folder.rglob('*'):
   if p.is_file():protected[p.relative_to(root).as_posix()]=sha(p)
  for n in read(folder/'sources.sha256.json'):
   if not n.startswith('generated:'):protected[n]=sha(within(root,n))
 expected={r['mutation']:r for r in matrix['negative']};actual={r['mutation']:r for r in index['negative_controls']};assert len(actual)==len(index['negative_controls'])and set(actual)==set(expected)
 faults=[]
 for name,wanted in sorted(expected.items()):
  row=actual[name];folder=within(root,row['evidence']);case=read(folder/'case.json');assert all(case[k]==wanted[k]for k in ('mutation','target','suite','top','patch'))
  exits=[case[k]for k in ('process_exit','return_code')if k in case]
  assert case['detected']and case['normal_completion']and exits and all(code==1 for code in exits),(name,'missing or inconsistent captured runner exit')
  original=within(root,case['target']).read_bytes();assert hashlib.sha256(original).hexdigest()==case['original_sha256'];mutated=within(root,case['target']).read_text(encoding='utf-8-sig')
  for patch in case['patch']:
   assert mutated.count(patch['before'])==patch.get('occurrences',1),(name,'semantic patch occurrence mismatch');mutated=mutated.replace(patch['before'],patch['after'])
  assert mutated==within(folder,case['mutant_file']).read_text(encoding='utf-8-sig'),(name,'mutant differs from declared semantic patch')
  assert sha(within(folder,case['mutant_file']))==case['mutated_sha256'],(name,'compiled mutant bytes changed')
  count=sources(root,folder,case);g=graph(root,folder,dict(top=case['top'],suite=case['suite']),case)
  log=(folder/'sim.log').read_text(errors='replace');values=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  assert '$finish called'in log and '[FAIL'in log and re.search(r'PASS\s+'+re.escape(case['top'])+r'\b|\[TB\]\s*'+re.escape(case['top'])+r'\s+done',log)
  assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and '[SKIP]'not in log
  assert values==case['error_counts']and any(values)
  if case.get('required_marker'):assert case['required_marker']in log
  faults.append(dict(mutation=name,source_bindings=count,compiler_graph=g,raw_log_sha256=sha(folder/'sim.log')))
  for p in folder.rglob('*'):
   if p.is_file():protected[p.relative_to(root).as_posix()]=sha(p)
  for n in read(folder/'sources.sha256.json'):
   if not n.startswith('generated:'):protected[n]=sha(within(root,n))
 # Recheck the current serial algorithm, its independent transition table,
 # real64k HDL observations and the full frozen public gain/timing oracle.
 proof_path=within(root,index['serial_volume_proof']);proof=read(proof_path);assert proof['accepted']and proof['rtl_sha256']==sha(root/'safevision/rtl/audio/v3_audio_volume.v')
 helper=root/'safevision/tools/prove_v3_volume_serial.py';assert proof['proof_script_sha256']==sha(helper)
 tree=ast.parse(helper.read_text());tokens=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='required'for t in n.targets))
 code=re.sub(r'\s+','',(root/'safevision/rtl/audio/v3_audio_volume.v').read_text());assert all(token in code for token in tokens)
 transitions=[]
 for rem in range(100):
  for bit in range(2):
   q,r=divmod(2*rem+bit,100);assert 0<=r<100 and 100*q+r==2*rem+bit
   transitions.append(dict(remainder=rem,input_bit=bit,quotient_bit=q,next_remainder=r))
 assert proof['transition_table']==transitions and proof['state_cases']==200 and proof['dividend_bits']==30 and proof['divisor']==100
 assert(proof['left_publication_active_edge'],proof['right_publication_active_edge'])==(37,74)
 assert(1<<23)*100<1<<30 and ((1<<30)-1)//100<1<<24
 folder,meta=positive_meta['tb_v3_volume_serial_step349'];assert meta['data_comparisons']==64000 and proof['native_log_sha256']==sha(folder/'sim.log')
 assert 'tb_v3_volume_serial'in positive_meta and 'tb_v3_volume_dsp_equivalence'in positive_meta
 protected[proof_path.relative_to(root).as_posix()]=sha(proof_path)
 # The congestion-first profile changes native option validation, not RTL.
 # Recheck its real TD readback and replay all six rejection controls.
 if any(stage=='route'and key=='post_route_opt'for stage,key,value in build_parameters(root,'hd')):
  folder=within(root,index['native_route_option_selftest']);meta=read(folder/'summary.json')
  assert meta['accepted']and not meta['functional_approval']and not meta['routed_STA_approval']and not meta['bitgen_performed']
  assert meta['checker_sha256']==sha(root/'safevision/tools/v3_sources.py')and meta['test_sha256']==sha(folder/'test_route_ack464.py')
  assert len(meta['records'])==8
  for mode in ('base','hd'):
   rows={r['name']:r for r in meta['records']if r['mode']==mode};assert len(rows)==4 and all(r['accepted']for r in rows.values())
   actual=folder/'native'/mode;row=rows['actual_native_ack'];assert row['process_exit']==0 and native_parameters(root,actual,stages=('route',))==row['values']
   log=(actual/'native.log').read_text(errors='replace');assert 'ROUTE_PARAM_NATIVE_ACK_COMPLETE'in log and not re.search(r'(?im)^\s*ERROR:|ROUTE OPTION QUERY FAILED',log)
   for kind in ('wrong_hidden_value','missing_hidden_value','wrong_ordinary_value'):
    assert rows[kind]['rejected']
    try:native_parameters(root,folder/kind/mode,stages=('route',))
    except (ValueError,FileNotFoundError):pass
    else:raise AssertionError('tampered route acknowledgement accepted: '+mode+'/'+kind)
  for p in folder.rglob('*'):
   if p.is_file():protected[p.relative_to(root).as_posix()]=sha(p)
 # A real-board failure exposed a shared error in ADC and its copied table.
 # Recover the four physical labels from the original vendor PDF, replay all
 # eleven rejection cases, and require the old real routed pads to be refused.
 folder=within(root,index['physical_key_selftest']);meta=read(folder/'summary.json')
 from check_v3_board_reference import check as board_check,FLOW
 from pypdf import PdfReader
 assert meta['accepted']and meta['positive_cases']==1 and meta['negative_cases']==11
 assert meta['checker_sha256']==sha(root/'safevision/tools/check_v3_board_reference.py')
 assert meta['test_script_sha256']==sha(folder/'test_key_contract477.py')
 assert meta['source_adc_sha256']==sha(root/FLOW/'v3_board.adc')and meta['source_reference_sha256']==sha(root/FLOW/'board_reference.json')
 assert sha(folder/'manual2410.pdf')==meta['original_manual_sha256']=='e6d066fdc433259697bcf5dfe9eb791cf8a87d289c75e69fa40172d716afccfe'
 page=PdfReader(folder/'manual2410.pdf').pages[18].extract_text()
 assert page==(folder/'manual2410_printed_p19.txt').read_text(encoding='utf-8')
 keys=dict(re.findall(r'\b(KEY[1-4])\s+([A-RT]\d+)\b',page))
 assert keys==meta['extracted_physical_key_balls']=={'KEY1':'A2','KEY2':'B2','KEY3':'B1','KEY4':'C1'}
 assert len(meta['records'])==12 and len({r['name']for r in meta['records']})==12
 for row in meta['records']:
  assert row['accepted']and row['positive']==(row['name']=='positive')
  case_root=folder/row['name'];captured=read(case_root/'case.json');assert captured==row
  try:actual=board_check(case_root)
  except ValueError:assert not row['positive']and row['rejected']
  else:assert row['positive']and not row['rejected']and actual==row['result']
 for n in ('v3_board.adc','board_reference.json','v3_board.sdc'):
  assert (folder/'positive'/FLOW/n).read_bytes()==(root/FLOW/n).read_bytes()
 try:board_check(root,(folder/'old_route.area').read_text())
 except ValueError as e:assert str(e)==meta['old_route_rejection']
 else:raise AssertionError('old swapped real PAD mapping incorrectly accepted')
 for p in folder.rglob('*'):
  if p.is_file():protected[p.relative_to(root).as_posix()]=sha(p)
 folder=within(root,index['physical_gesture_selftest']);extra=read(folder/'result.json')
 report=read(folder/'results.json');assert report['complete']and report['results'][0]['status']=='PASS'
 assert extra['producer_process_exit']==0 and extra['accepted_native_runner']and not extra['source_overrides']
 assert extra['data_comparisons']==89 and extra['suite']=='key_gestures478'and extra['top']=='tb_v3_key_gestures478'
 sources(root,folder);graph(root,folder,extra);assert audit_file(folder/'sim.log',True)['accepted']
 for n in read(folder/'sources.sha256.json'):protected[n]=sha(within(root,n))
 for p in folder.rglob('*'):
  if p.is_file():protected[p.relative_to(root).as_posix()]=sha(p)
 if alias_extension:
  from audit_v3_media_alias510 import audit as audit_media_alias
  audit_media_alias(root)
  for p in(root/'evidence/v3/multires_alias_261022').rglob('*'):
   if p.is_file():protected[p.relative_to(root).as_posix()]=sha(p)
 if flexible_extension:
  from audit_v3_flexible_media537 import audit as flexible_audit
  flexible=flexible_audit(root,index,matrix)
  assert flexible['accepted']and not flexible['release_ready']
  protected.update(flexible['proof_sha256'])
 from audit_v3_compact_ingress616 import audit as compact_ingress_audit
 compact_ingress=compact_ingress_audit(root,index,repository)
 assert compact_ingress['accepted']and not compact_ingress['release_ready']
 protected.update(compact_ingress['proof_sha256'])
 for p in(root/'safevision/tools').rglob('*.py'):protected[p.relative_to(root).as_posix()]=sha(p)
 gui=[check_gui(root,m)for m in ('base','hd')]
 result=dict(accepted=bool(index['complete']and not missing_positive),profile=index['profile'],source_build_commit=matrix['source_build_commit'],required_positive_records_including_aliases=expected_records,positive_unique_tops=len(records),missing_positive=missing_positive,strict_normal_ending_mutants=expected_negative,physical_inputs=expected_physical,positive=records,negative=faults,source_sha256=hardware,proof_sha256=protected,gui_cli=gui,current_serial_division_proof=True,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False,release_ready=False)
 if flexible_extension:result['flexible_media_auxiliary']={k:v for k,v in flexible.items()if k!='proof_sha256'}
 result['compact_ingress_auxiliary']={k:v for k,v in compact_ingress.items()if k!='proof_sha256'}
 if legacy_ports is not None:result['legacy_ordered_ports']=legacy_ports
 return result

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--source-repo',type=Path,required=True);ap.add_argument('--manifest',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--inspect-incomplete',action='store_true',help='Audit available cases but return2 and never approve incomplete evidence');a=ap.parse_args()
 try:r=audit(a.repo.resolve(),a.manifest,a.source_repo.resolve(),a.inspect_incomplete);code=0 if r['accepted']else 2
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e),release_ready=False);code=1
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2)+'\n');print('FOUR FEATURE EVIDENCE '+('PASS'if code==0 else 'INCOMPLETE'if code==2 else 'REJECTED: '+r['error']),flush=True);return code
if __name__=='__main__':sys.exit(main())
