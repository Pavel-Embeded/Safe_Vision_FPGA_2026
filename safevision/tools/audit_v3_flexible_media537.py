"""Read-only FLEX requirements, production wiring and independent-oracle audit.

This auxiliary gate does not approve simulation, STA, bitstreams or hardware.
``requirements(root,index,matrix)`` checks the extended definition inventory.
``audit(root,index,matrix)`` additionally checks production assembly, both
independent numerical oracles and returns proof_sha256 for the parent auditor.

Before importing the new matrix, --requirements-preview constructs only an
in-memory prospective matrix and runs rejection selftests. Its accepted field
is always false: it never certifies an unimported or incomplete profile.
"""
from __future__ import annotations
import argparse,copy,hashlib,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True

ROOT=Path(__file__).resolve().parents[2]
PROFILE='four_features_261020'
INDEX='evidence/v3/four_features_261020/acceptance.json'
ARCHIVE='evidence/v3/flex_media_261022'
TOP='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
# Reviewed original definitions, sorted by top/mutation then canonical JSON.
# These hashes exclude source commits, physical fingerprints and evidence paths.
# The existing digest includes the complete FLEX width guard. The exact
# coherent counter-zero-flag extension is separately checked and documented
# below; all205 original fault identities remain mandatory.
BASE_POSITIVE_SHA256='0f5546944127f9eab173864409a2365d63c29a3ce2d75ed4442dc6db88fc15d6'
BASE_NEGATIVE_SHA256='b46516f662e79eda723982bbe098527e3afc19653d3c5441495b76d162b85a70'

NEW_POSITIVE=(
 ('tb_v3_flexible540','flexible540'),
 ('tb_v3_directory_limit550','directory_limit550'),
 ('tb_v3_directory_fault550','directory_fault550'),
 ('tb_v3_wav_retry550','wav_retry550'),
 ('tb_v3_flexible_fs550','flexible_fs550'),
 ('tb_v3_flexible_retry_fs550','flexible_retry_fs550'),
 ('tb_v3_flexible_bmp542','flexible_bmp542'),
 ('tb_v3_flexible_bmp_bounds551','flexible_bmp_bounds551'),
 ('tb_v3_spectrum539','spectrum539'),
 ('tb_v3_progress_watchdog_base561','progress_watchdog_base561'),
 ('tb_v3_progress_watchdog_hd561','progress_watchdog_hd561'),
 ('tb_v3_progress_recovery561','progress_recovery561'),
 ('tb_v3_progress_recovery_hd561','progress_recovery_hd561'),
)
STRICT_RUNNER='safevision/tools/run_v3_sim_flexible.py'
FULL_GENERATOR='safevision/verification/fixtures/generate_flexible_fs550.py'
FULL_RUNTIME=('resident_card.mem','expected0.mem','expected1.mem','expected2.mem','expected3.mem','lifecycle_pcm.mem','flexible_metadata.mem','flexible_fs550.reference.json')
GENERATED_REQUIREMENTS={
 'directory_fault550':(FULL_GENERATOR,(),FULL_RUNTIME),
 'flexible_fs550':(FULL_GENERATOR,(),FULL_RUNTIME),
 'flexible_retry_fs550':('safevision/verification/fixtures/generate_flexible_retry_fs550.py',(FULL_GENERATOR,),FULL_RUNTIME),
 'wav_retry550':('safevision/verification/fixtures/generate_wav_retry550.py',(),('wav_retry_disk.mem','wav_retry_pcm.mem','wav_retry550.reference.json')),
}

def _mutation(name,target,suite,top,before,after):
 return dict(mutation=name,target=target,suite=suite,top=top,patch=[dict(before=before,after=after)])

NEW_NEGATIVE=(
 _mutation('flex_fs_directory_key_offset','safevision/rtl/storage/v3_flexible_media_index.v','flexible540','tb_v3_flexible540',"sel_key<=current_index+16'd1;","sel_key<=current_index+16'd2;"),
 _mutation('flex_fs_lfn_checksum_bypass','safevision/rtl/storage/v3_fat_name_store.v','flexible540','tb_v3_flexible540','alias_checksum==chain_checksum',"1'b1"),
 _mutation('flex_fs_stereo_channels_swapped','safevision/rtl/storage/v3_wav_source.v','wav_retry550','tb_v3_wav_retry550',"{96'd0,sample}","{96'd0,sample[15:0],sample[31:16]}"),
 _mutation('flex_fs_retry_cursor_stuck','safevision/rtl/storage/v3_wav_source.v','wav_retry550','tb_v3_wav_retry550',"retry_cursor<=directory_index+1'b1;","retry_cursor<=16'd0;"),
 _mutation('flex_fs_partial_directory_commit','safevision/rtl/storage/sd_bmp_player.v','directory_fault550','tb_v3_directory_fault550','dir_bad||(FLEX_FILES&&dn_ec!=`ERR_NONE)','dir_bad'),
 _mutation('flex_bmp_dib_overlap_accepted','safevision/rtl/media/bmp_parser.v','flexible_bmp_bounds551','tb_v3_flexible_bmp_bounds551','wire dib_ok    = dib_ge40_r && (!FLEX_PIXELS || dib_within_offset_r);','wire dib_ok    = dib_ge40_r;'),
 _mutation('flex_bmp_unsampled_tail_truncation_accepted','safevision/rtl/media/v3_bmp_normalizer.v','flexible_bmp_bounds551','tb_v3_flexible_bmp_bounds551',"if(last_row_byte && src_row==h-1'b1)state<=FINISH;","if(1'b1)state<=FINISH;"),
 _mutation('flex_fft_fft_sign','safevision/rtl/video/v3_audio_spectrum.v','spectrum539','tb_v3_spectrum539','wi=-sine_value','wi=sine_value'),
 _mutation('flex_fft_bank_commit','safevision/rtl/video/v3_audio_spectrum.v','spectrum539','tb_v3_spectrum539','display_bank<=pending_bank','display_bank<=display_bank'),
 _mutation('flex_fft_peak_decay','safevision/rtl/video/v3_audio_spectrum.v','spectrum539','tb_v3_spectrum539',"previous_peak-7'd1",'previous_peak'),
 _mutation('flex_fft_log_scale','safevision/rtl/video/v3_audio_spectrum.v','spectrum539','tb_v3_spectrum539',"log_height=7'd60+","log_height=7'd59+"),
 _mutation('flex_fft_palette','safevision/rtl/video/v3_audio_spectrum.v','spectrum539','tb_v3_spectrum539',"16'h05bf;","16'h031f;"),
 _mutation('flex_progress_base_load_progress_disabled','safevision/rtl/control/v3_supervisor.v','progress_watchdog_base561','tb_v3_progress_watchdog_base561','wire load_progress=PROGRESSIVE_LOAD && (progress_heartbeat || mem_heartbeat);',"wire load_progress=1'b0;"),
 _mutation('flex_progress_base_wait_progress_disabled','safevision/rtl/control/media_recovery_ctrl.v','progress_recovery561','tb_v3_progress_recovery561','wire wait_progress=PROGRESSIVE_WAIT && progress;',"wire wait_progress=1'b0;"),
 _mutation('flex_progress_hd_load_progress_disabled','safevision/rtl/hd/v3_supervisor.v','progress_watchdog_hd561','tb_v3_progress_watchdog_hd561','wire load_progress=PROGRESSIVE_LOAD && (progress_heartbeat || mem_heartbeat);',"wire load_progress=1'b0;"),
 _mutation('flex_progress_hd_wait_progress_disabled','safevision/rtl/hd/media_recovery_ctrl.v','progress_recovery_hd561','tb_v3_progress_recovery_hd561','wire wait_progress=PROGRESSIVE_WAIT && progress;',"wire wait_progress=1'b0;"),
)

def require(ok,message):
 if not ok:raise ValueError(message)
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def within(root,name):
 path=(root/name).resolve()
 require(path.is_relative_to(root.resolve()),'path escaped repository: '+str(name))
 return path
def _object(root,value):return value if isinstance(value,dict)else read(within(root,value))
def definition_hash(rows,key):
 raw=json.dumps(sorted(rows,key=lambda row:row[key]),sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')
 return hashlib.sha256(raw).hexdigest()
def _normalized_patch(row):
 # Explicit occurrences=1 and its documented default are equivalent.
 result=copy.deepcopy(row)
 for patch in result['patch']:
  if patch.get('occurrences')==1:patch.pop('occurrences')
 return result

def strict_manifests(root):
 """The new inventory cannot opt out or omit an imported generator dependency."""
 root=Path(root).resolve();result={}
 for top,suite in NEW_POSITIVE:
  name='safevision/build/manifests/'+suite+'_sim.json';manifest=read(within(root,name))
  require(manifest.get('strict_generated_inputs')==1,'new FLEX suite omitted strict input binding: '+suite)
  require(manifest.get('native_runner')==STRICT_RUNNER,'new FLEX suite omitted strict native runner: '+suite)
  require(manifest['tops']==[top],'new FLEX manifest changed the selected independent top: '+suite)
  generator,deps,runtime=GENERATED_REQUIREMENTS.get(suite,(None,(),()))
  expected_generators={top:generator}if generator else{}
  require(manifest.get('generators',{})==expected_generators,'new FLEX generator selection changed: '+suite)
  require(manifest.get('generator_dependencies')==list(deps),'new FLEX generator dependencies omitted or changed: '+suite)
  require(manifest.get('generated_assets')==list(runtime),'new FLEX generated runtime inventory omitted or changed: '+suite)
  require(len(manifest['sources'])==len(set(manifest['sources'])),'new FLEX source manifest contains duplicates: '+suite)
  result[suite]=dict(manifest=name,sha256=sha(root/name),native_runner=STRICT_RUNNER,generator_dependencies=len(deps),generated_assets=len(runtime))
 require(within(root,STRICT_RUNNER).is_file(),'strict FLEX runner missing')
 return dict(verified=True,suites=result,native_runner=STRICT_RUNNER,native_runner_sha256=sha(root/STRICT_RUNNER))

def requirements(root,index,matrix):
 """Verify fixed 303/221 inventory and unchanged reviewed 290/205 definitions.

 Returns required counts and definition hashes; no acceptance/approval claim.
 Raises on missing/extra/weakened definitions or a mismatched physical snapshot.
 """
 root=Path(root).resolve();index=_object(root,index);matrix=_object(root,matrix)
 require(index['profile']==matrix['profile']==PROFILE,'unexpected profile')
 require(index.get('flexible_media_extension_schema')==1,'FLEX extension schema absent')
 require(index['source_build_commit']==matrix['source_build_commit'],'source commit identities disagree')
 require(len(matrix['positive'])==303 and len(matrix['negative'])==221 and matrix['positive_records_including_aliases']==304,'FLEX requires303 independent positive tops,221 controls and304 records including historical aliases')
 pos={r['top']:r for r in matrix['positive']};neg={r['mutation']:r for r in matrix['negative']}
 require(len(pos)==303 and len(neg)==221,'duplicate positive top/negative mutation')
 wanted_pos={top:dict(top=top,suite=suite,legacy=False)for top,suite in NEW_POSITIVE}
 wanted_neg={r['mutation']:r for r in NEW_NEGATIVE}
 for top,row in wanted_pos.items():require(pos.get(top)==row,'fixed new top/suite changed or missing: '+top)
 actual_flex={name for name in neg if name.startswith('flex_')}
 require(actual_flex==set(wanted_neg),'fixed new FLEX mutation set changed')
 for name,row in wanted_neg.items():require(_normalized_patch(neg[name])==row,'reviewed FLEX semantic mutation changed: '+name)
 baseline_pos=[r for r in matrix['positive']if r['top']not in wanted_pos]
 baseline_neg=[r for r in matrix['negative']if not r['mutation'].startswith('flex_')]
 require(len(baseline_pos)==290 and len(baseline_neg)==205,'historical matrix was removed or replaced')
 # The counter-width fault still shortens SOURCE_W by exactly one bit.
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
 pos_digest=definition_hash(baseline_pos,'top');neg_digest=definition_hash(baseline_neg,'mutation')
 require(pos_digest==BASE_POSITIVE_SHA256,'historical290 positive requirements changed')
 require(neg_digest==BASE_NEGATIVE_SHA256,'historical205 negative semantic definitions changed')
 if str(root/'safevision/tools')not in sys.path:sys.path.insert(0,str(root/'safevision/tools'))
 from v3_sources import snapshot
 physical=snapshot(root);strict=strict_manifests(root)
 require(len(physical)==205 and matrix['physical_source_sha256']==physical,'FLEX requires the current explicit205 physical inputs')
 return dict(requirements_verified=True,expected_positive=303,expected_negative=221,expected_records=304,expected_physical=205,new_positive=13,new_negative=16,base_positive=290,base_negative=205,base_positive_definition_sha256=pos_digest,base_negative_definition_sha256=neg_digest,actual_base_negative_definition_sha256=actual_neg_digest,reviewed_counter_fault_model=counter_model,new_positive_tops=sorted(wanted_pos),new_mutations=sorted(wanted_neg),strict_native_inputs=strict)

def _strip_comments(text):
 return re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*[\s\S]*?\*/',lambda match:match.group(1)or' ',text)
def _paren(text,opening):
 require(opening<len(text)and text[opening]=='(','missing parenthesis')
 depth=0;quoted=False;escaped=False
 for end in range(opening,len(text)):
  c=text[end]
  if quoted:
   if escaped:escaped=False
   elif c=='\\':escaped=True
   elif c=='"':quoted=False
   continue
  if c=='"':quoted=True
  elif c=='(':depth+=1
  elif c==')':
   depth-=1
   if depth==0:return text[opening+1:end],end+1
 raise ValueError('unbalanced production instance')
def _instance(text,module,name):
 hits=list(re.finditer(r'\b'+re.escape(module)+r'\s*#\s*\(',text))
 require(len(hits)==1,'production module must be instantiated exactly once: '+module)
 params,end=_paren(text,hits[0].end()-1)
 tail=re.match(r'\s*'+re.escape(name)+r'\s*\(',text[end:])
 require(tail is not None,'unexpected production instance name: '+module)
 ports,_=_paren(text,end+tail.end()-1)
 return params,ports
def _wire(ports,name):
 hits=re.findall(r'\.\s*'+re.escape(name)+r'\s*\(\s*([A-Za-z_][A-Za-z0-9_$]*)\s*\)',ports)
 require(len(hits)==1,'port must connect once to a plain named net: '+name)
 return hits[0]
def _production_wiring(root):
 text=_strip_comments((root/TOP).read_text(encoding='utf-8-sig'))
 instances={key:_instance(text,module,key)for key,module in [('player','sd_bmp_player'),('audio','v3_audio_system'),('video','v3_video_display_core'),('supervisor','v3_supervisor')]}
 settings=[('FLEX_FILES','player'),('PREINDEXED','audio'),('FLEX_SPECTRUM','video'),('PROGRESSIVE_LOAD','supervisor')]
 for parameter,instance in settings:
  expression=r'\.\s*'+parameter+r'\s*\(\s*1\s*\)'
  require(len(re.findall(expression,text))==1 and len(re.findall(expression,instances[instance][0]))==1,'production feature enable must appear exactly once on its owning module: '+parameter)
 ports=('media_descriptor_valid','media_descriptor_ready','media_descriptor_slot','media_descriptor','media_descriptor_found')
 nets={port:_wire(instances['player'][1],port)for port in ports}
 require(len(set(nets.values()))==5,'descriptor ready/valid/data/slot/found nets aliased')
 require(all(_wire(instances['audio'][1],port)==net for port,net in nets.items()),'player/audio descriptor nets disagree')
 clock=_wire(instances['player'][1],'clk')
 require(_wire(instances['audio'][1],'ref_clk')==clock,'descriptor endpoints are not in the same REF clock domain')
 return dict(verified=True,top=TOP,feature_parameters={parameter:1 for parameter,_ in settings},descriptor_nets=nets,descriptor_ref_clock=clock)

def audit(root,index,matrix):
 """Verify auxiliary evidence and return proof_sha256 for the parent gate.

 ``accepted`` is scoped to this auxiliary gate. Full simulation, routed STA,
 bitstreams, programming and hardware acceptance remain expressly unapproved.
 """
 root=Path(root).resolve();index=_object(root,index);matrix=_object(root,matrix)
 inventory=requirements(root,index,matrix);wiring=_production_wiring(root)
 from check_v3_spectrum_oracle537 import check as spectrum_check
 from check_v3_bmp_oracle537 import check as bmp_check
 spectrum=spectrum_check(root);bmp=bmp_check(root)
 require(spectrum['accepted']and bmp['accepted'],'independent numerical oracle rejected')
 proofs={}
 def protect(name,expected=None):
  path=within(root,name);require(path.is_file(),'required proof file missing: '+name);digest=sha(path)
  if expected is not None:require(digest==expected,'oracle proof changed during audit: '+name)
  proofs[path.relative_to(root).as_posix()]=digest
 for name in ('safevision/tools/audit_v3_flexible_media537.py','safevision/tools/check_v3_sim_graph.py',STRICT_RUNNER,'safevision/tools/check_v3_spectrum_oracle537.py','safevision/tools/check_v3_bmp_oracle537.py',TOP):protect(name)
 for name,meta in spectrum['files'].items():protect(name,meta['sha256'])
 for name,digest in bmp['inputs_sha256'].items():protect(name,digest)
 archive=within(root,ARCHIVE);require(archive.is_dir(),'new FLEX evidence has not been imported')
 positive={r['top']:r for r in index['positive_tests']};negative={r['mutation']:r for r in index['negative_controls']}
 for top,suite in NEW_POSITIVE:
  row=positive.get(top);expected=ARCHIVE+'/positive/'+top
  require(row is not None and row['suite']==suite and row['legacy']is False and row['evidence']==expected,'new positive evidence missing or relocated: '+top)
  folder=within(root,expected);meta=read(folder/'result.json')
  require(sha(folder/'result.json')==row['result_sha256']and meta['suite']==suite and meta['top']==top and meta['status']=='PASS'and not meta['source_overrides']and meta['accepted_native_runner'],'new positive producer metadata rejected: '+top)
  require(meta.get('strict_generated_inputs')==1 and meta.get('native_runner')==STRICT_RUNNER,'new positive used an old lax native runner: '+top)
  manifest_name='safevision/build/manifests/'+suite+'_sim.json';protect(manifest_name);manifest=read(root/manifest_name)
  from check_v3_sim_graph import strict_inputs
  strict_inputs(root,folder,manifest,top)
  tests=manifest.get('test_sources',{}).get(top,['safevision/verification/unit/'+top+'.sv'])
  if isinstance(tests,str):tests=[tests]
  selected=list(manifest['sources'])+tests+manifest.get('assets',[])+manifest.get('generator_dependencies',[])
  generator=manifest.get('generators',{}).get(top)
  if generator:selected.append(generator)
  for name in selected:protect(name)
 for definition in NEW_NEGATIVE:
  name=definition['mutation'];row=negative.get(name);expected=ARCHIVE+'/negative/'+name
  require(row is not None and row['evidence']==expected,'new negative evidence missing or relocated: '+name)
  case=read(within(root,expected)/'case.json')
  require(_normalized_patch({key:case[key]for key in ('mutation','target','suite','top','patch')})==definition,'new negative evidence semantic definition changed: '+name)
  require(case['process_exit']==1 and case['normal_completion']and case['detected'],'new control did not finish with detected assertion errors: '+name)
  manifest=read(root/'safevision/build/manifests'/(case['suite']+'_sim.json'))
  strict_inputs(root,within(root,expected),manifest,case['top'])
 for folder in ('flexible540','bmp542','bmp_bounds551','spectrum539'):
  directory=root/'safevision/verification/assets'/folder
  require(directory.is_dir(),'new feature asset folder missing: '+str(directory))
  for path in directory.rglob('*'):
   if path.is_file():protect(path.relative_to(root).as_posix())
 for path in archive.rglob('*'):
  if path.is_file():protect(path.relative_to(root).as_posix())
 # Native physical identity is independently bound by the parent auditor.
 for name,digest in matrix['physical_source_sha256'].items():protect(name,digest)
 return dict(accepted=True,scope='Auxiliary FLEX requirements, assembly and independent assets only',requirements=inventory,production_wiring=wiring,spectrum_oracle=spectrum,bmp_oracle=bmp,proof_sha256=proofs,protected_files=len(proofs),full_profile_approved=False,rtl_simulation_verified=False,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False,release_ready=False)

def requirements_preview(root,index,matrix):
 """Read-only prospective inventory and rejection selftest; never approval."""
 root=Path(root).resolve();index=copy.deepcopy(_object(root,index));matrix=copy.deepcopy(_object(root,matrix))
 require(len(matrix['positive'])==290 and len(matrix['negative'])==205,'requirements preview expects the not-yet-extended matrix')
 require(definition_hash(matrix['positive'],'top')==BASE_POSITIVE_SHA256 and definition_hash(matrix['negative'],'mutation')==BASE_NEGATIVE_SHA256,'reviewed base definitions changed before extension')
 matrix['positive'] += [dict(top=top,suite=suite,legacy=False)for top,suite in NEW_POSITIVE]
 matrix['negative'] += copy.deepcopy(list(NEW_NEGATIVE));matrix['positive_records_including_aliases']=304
 if str(root/'safevision/tools')not in sys.path:sys.path.insert(0,str(root/'safevision/tools'))
 from v3_sources import snapshot
 matrix['physical_source_sha256']=snapshot(root);index['flexible_media_extension_schema']=1
 good=requirements(root,index,matrix);controls=[]
 def reject(name,change):
  damaged=copy.deepcopy(matrix);change(damaged)
  try:requirements(root,index,damaged)
  except (ValueError,KeyError) as error:controls.append(dict(name=name,rejected=True,reason=str(error)))
  else:raise ValueError('requirements selftest failed to reject '+name)
 reject('historical_positive_replaced',lambda m:m['positive'][0].update(top='removed_historical_test'))
 reject('historical_negative_weakened',lambda m:m['negative'][0]['patch'][0].update(after='unreviewed_semantic_change'))
 reject('new_top_missing',lambda m:m['positive'].pop())
 reject('new_suite_changed',lambda m:m['positive'][-1].update(suite='wrong_suite'))
 reject('new_mutation_replaced',lambda m:m['negative'][-1].update(mutation='flex_unknown'))
 reject('new_mutation_weakened',lambda m:m['negative'][-1]['patch'][0].update(after="wire wait_progress=PROGRESSIVE_WAIT && progress;"))
 reject('historical_alias_record_missing',lambda m:m.update(positive_records_including_aliases=303))
 reject('physical_input_missing',lambda m:m['physical_source_sha256'].pop(next(iter(m['physical_source_sha256']))))
 return dict(accepted=False,requirements_preview=True,requirements_verified=True,complete=False,prospective=good,rejection_controls=controls,source_commit_binding_verified=False,full_profile_approved=False,rtl_simulation_verified=False,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False,release_ready=False)

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--repo',type=Path,default=ROOT);parser.add_argument('--index',default=INDEX)
 parser.add_argument('--requirements-preview',action='store_true')
 args=parser.parse_args();root=args.repo.resolve()
 try:
  index=read(within(root,args.index));matrix=read(within(root,index['matrix']))
  result=requirements_preview(root,index,matrix)if args.requirements_preview else audit(root,index,matrix)
 except Exception as error:
  print(json.dumps(dict(accepted=False,error=type(error).__name__+': '+str(error),release_ready=False),ensure_ascii=False,indent=2));return 1
 print(json.dumps(result,ensure_ascii=False,indent=2));return 0

if __name__=='__main__':raise SystemExit(main())
