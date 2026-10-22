"""Required compact-ingress qualification; raw HDL evidence only, never STA approval."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
RUNNER='safevision/tools/run_v3_sim_flexible.py'
SUITE='compact_ingress616'
MANIFEST='safevision/build/manifests/compact_ingress616_sim.json'
TB='safevision/verification/unit/tb_v3_compact_ingress616.sv'
TARGET='safevision/rtl/audio/v3_pcm_ingress_shared_fifo.v'
AUDIO='safevision/rtl/audio/v3_audio_system.v'
REFERENCE='safevision/verification/models/v3_pcm_ingress_shared_fifo_default_reference616.v'
ORIGINAL='safevision/verification/models/v3_pcm_ingress_shared_fifo_default_reference616.original.v'
FREEZE='safevision/verification/models/v3_pcm_ingress_shared_fifo_default_reference616.freeze.json'
ORIGIN_COMMIT='2bfda8b07b48896776fed0c2242ab493f949874d'
ORIGIN_SHA='f8325dfa2ea4ff2740d3c4d9475be3d2c496d0e20a5303cbd463eb84ac689b17'
ARCHIVE='evidence/v3/compact_ingress_261022'
CREDIT_TOP='tb_v3_ingress_credit616'
EXISTING_CREDIT='safevision/verification/unit/tb_v3_ingress_credit.sv'
EXISTING_CREDIT_SHA='9bdd142644107358a50b7eb8f916c73ccb8791e552ccc71003200fd39914ad94'
POSITIVE={'tb_v3_ingress_compact616':2099,'tb_v3_ingress_legacy616':2270,'tb_v3_ingress_prefill616':4100,'tb_v3_audio_depth616':10}
NEGATIVE=[dict(mutation='compact_admit_default632',target=TARGET,suite=SUITE,top=CREDIT_TOP,patch=[dict(before='words<=((1<<AW)-392)',after="words<=11'd632")],errors=782),dict(mutation='ceil_credit_no_rounding',target=TARGET,suite=SUITE,top=CREDIT_TOP,patch=[dict(before="+21'd1366",after="+21'd0")],errors=4092)]
# The complete authored compiler list is frozen separately from actual analysis;
# neither dropping a manifest member nor dropping an analyzed file is accepted.
SOURCES=['safevision/rtl/common/sv_async_fifo.v', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_ip.v', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_eram.v', 'safevision/rtl/video/video_cdc/video_cdc_mailbox.v', 'safevision/rtl/storage/fat32_directory_scanner.v', 'safevision/rtl/storage/fat32_cluster_walker.v', 'safevision/rtl/storage/v3_file_streamer.v', 'safevision/rtl/media/wav_parser.v', 'safevision/rtl/storage/v3_wav_source.v', 'safevision/rtl/audio/v3_pcm_ring.v', 'safevision/rtl/audio/v3_audio_system.v', 'safevision/rtl/audio/alarm_tone_gen.v', 'safevision/rtl/audio/audio_priority_arbiter.v', 'safevision/rtl/audio/v3_audio_priority_serial.v', 'safevision/rtl/audio/audio_energy.v', 'safevision/rtl/audio/hdmi_acr.v', 'safevision/rtl/storage/v3_file_streamer_ctx.v', 'safevision/rtl/storage/v3_cluster_walker_ctx.v', 'safevision/rtl/media/v3_wav_parser_ctx.v', 'safevision/rtl/audio/v3_audio_volume.v', 'safevision/rtl/audio/v3_pcm_packet_fifo.v', 'safevision/rtl/audio/v3_pcm_ingress_fifo.v', 'safevision/rtl/audio/v3_pcm_sample_fifo.v', 'safevision/rtl/audio/v3_pcm_ingress_shared_fifo.v', 'safevision/rtl/media/v3_wav_parser_compact_ctx.v', 'safevision/rtl/storage/v3_file_streamer_compact_ctx.v', 'safevision/rtl/audio/v3_audio_prefill_compare.v', 'safevision/rtl/storage/v3_fat_name_store.v', 'safevision/verification/models/v3_pcm_ingress_shared_fifo_default_reference616.v']
def require(ok,message):
 if not ok:raise ValueError(message)
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def within(root,name):
 p=(Path(root)/name).resolve();require(p.is_relative_to(Path(root).resolve()),'path escaped root: '+str(name));return p

def static(root,repository):
 root=Path(root);repository=Path(repository)
 process=subprocess.run(['git','-C',str(repository),'show',ORIGIN_COMMIT+':'+TARGET],capture_output=True)
 require(process.returncode==0,'frozen default FIFO Git object unavailable')
 raw=process.stdout;require(hashlib.sha256(raw).hexdigest()==ORIGIN_SHA,'frozen default FIFO origin changed')
 require(raw.count(b'module v3_pcm_ingress_shared_fifo(')==1,'unexpected frozen module declaration')
 renamed=raw.replace(b'module v3_pcm_ingress_shared_fifo(',b'module v3_pcm_ingress_shared_fifo_original616(')
 require((root/ORIGINAL).read_bytes()==raw and(root/REFERENCE).read_bytes()==renamed,'default reference differs from Git except allowed module rename')
 meta=read(root/FREEZE)
 require(meta==dict(origin_commit=ORIGIN_COMMIT,origin_path=TARGET,original_sha256=ORIGIN_SHA,reference_sha256=hashlib.sha256(renamed).hexdigest(),transform='Rename only the original module declaration, preserve every other byte'),'default reference metadata changed')
 current=(root/TARGET).read_text(encoding='utf-8-sig');old=raw.decode('utf-8-sig')
 def ports(t):i=t.index(' input wire rst');return re.sub(r'\s+','',t[i:t.index(');',i)])
 require(ports(current)==ports(old),'FIFO public port ABI changed')
 require('modulev3_pcm_ingress_shared_fifo#(parameterintegerAW=10)('in re.sub(r'\s+','',current),'generic AW10 default not preserved')
 code=re.sub(r'\s+','',(root/AUDIO).read_text(encoding='utf-8-sig'))
 require(code.count('v3_pcm_ingress_shared_fifo#(.AW(PREINDEXED?9:10))ingress_shared(')==1,'production FLEX compact selection missing/ambiguous')
 require(sha(root/EXISTING_CREDIT)==EXISTING_CREDIT_SHA,'existing4096/default +2048/compact credit coverage changed')
 manifest=read(root/MANIFEST);require(manifest.get('sources')==SOURCES,'compact manifest compiler list changed')
 tops=[CREDIT_TOP]+list(POSITIVE)
 require(manifest.get('tops')==tops and manifest.get('test_sources')=={top:[TB]for top in tops},'compact test top/source declarations changed')
 require(manifest.get('strict_generated_inputs')==1 and manifest.get('native_runner')==RUNNER,'compact qualification must use strict native runner')
 require(manifest.get('assets')==[]and manifest.get('generator_dependencies')==[]and manifest.get('generated_assets')==[],'unexpected hidden/generated compact input')
 return dict(origin_commit=ORIGIN_COMMIT,origin_sha256=ORIGIN_SHA,reference_sha256=sha(root/REFERENCE),public_ports_preserved=True,default_AW=10,production_FLEX_AW=9)

def normal(folder,top,negative=False):
 folder=Path(folder);text=(folder/'sim.log').read_text(encoding='utf-8-sig',errors='replace')
 require('$finish called'in text and re.search(r'\[TB\]\s*'+re.escape(top)+r'\s+done\b',text),'missing normal HDL finish: '+str(folder))
 require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',text)and'[SKIP]'not in text,'crash/skip is not qualification')
 errors=[int(v)for v in re.findall(r'errors\s*=\s*(\d+)',text)];counts=[int(v)for v in re.findall(r'comparisons\s*=\s*(\d+)',text)]
 require(errors and counts,'missing independent HDL counters')
 if negative:require(any(errors)and'[FAIL]'in text,'mutant did not produce HDL mismatches')
 else:require(not any(errors)and'[FAIL]'not in text and'[PASS]'in text,'positive HDL assertion failed')
 for name in ('compile.log','compile.console.log','elab.log','elab.console.log'):
  p=folder/name;require(p.is_file(),'native stage log missing: '+name)
  require(not re.search(r'(?im)^\s*(?:ERROR:|FATAL\b|Fatal:)',p.read_text(errors='replace')),'native stage failed')
 return errors,counts[-1]

def checked_cases(root,positive,negative,repository):
 require(set(positive)==set(POSITIVE)and set(negative)=={r['mutation']for r in NEGATIVE},'exact4positive/2negative compact cases required')
 sys.path.insert(0,str(Path(root)/'safevision/tools'))
 from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 identity=static(root,repository);records=[];controls=[];proof={}
 for top,expected in POSITIVE.items():
  folder=Path(positive[top]);meta=read(folder/'result.json')
  require(meta.get('top')==top and meta.get('suite')==SUITE and meta.get('status')=='PASS'and meta.get('source_overrides')==[],'wrong/overridden compact positive metadata')
  require(meta.get('strict_generated_inputs')==1 and meta.get('native_runner')==RUNNER,'compact producer used lax runner')
  errors,count=normal(folder,top);require(count==expected==meta.get('data_comparisons'),'compact positive comparison coverage changed')
  captures=sources(root,folder);g=graph(root,folder,meta)
  require(g.get('strict_generated_inputs_verified'),'compact strict input graph not verified')
  records.append(dict(top=top,data_comparisons=count,source_bindings=captures,compiler_graph=g,raw_log_sha256=sha(folder/'sim.log')))
  for name in read(folder/'sources.sha256.json'):
   if not name.startswith('generated:'):proof[name]=sha(within(root,name))
 for definition in NEGATIVE:
  folder=Path(negative[definition['mutation']]);case=read(folder/'case.json')
  require({k:case[k]for k in('mutation','target','suite','top','patch')}=={k:definition[k]for k in('mutation','target','suite','top','patch')},'compact semantic mutation changed')
  raw=within(root,TARGET).read_bytes();changed=raw.decode('utf-8')
  for patch in definition['patch']:
   require(changed.count(patch['before'])==1,'compact semantic patch not unique');changed=changed.replace(patch['before'],patch['after'])
  require(case['mutant_file']=='mutant.v'and(folder/'mutant.v').read_bytes()==changed.encode('utf-8'),'compiled compact mutant differs from declared semantic change')
  require(case['original_sha256']==hashlib.sha256(raw).hexdigest()and case['mutated_sha256']==sha(folder/'mutant.v'),'compact mutant source hashes changed')
  require(case.get('process_exit')==1 and case.get('normal_completion')and not case.get('tool_failure'),'compact negative tool failure cannot qualify')
  errors,count=normal(folder,CREDIT_TOP,True);require(errors==[definition['errors']]==case.get('error_counts')and count==6144,'compact mutant counters changed')
  captures=sources(root,folder,case);g=graph(root,folder,dict(top=CREDIT_TOP,suite=SUITE),case)
  require(g.get('strict_generated_inputs_verified'),'compact mutant strict graph not verified')
  controls.append(dict(mutation=definition['mutation'],normal_completion=True,error_counts=errors,source_bindings=captures,compiler_graph=g,raw_log_sha256=sha(folder/'sim.log')))
  for name in read(folder/'sources.sha256.json'):
   if not name.startswith('generated:'):proof[name]=sha(within(root,name))
 for name in(REFERENCE,ORIGINAL,FREEZE,MANIFEST,TB,EXISTING_CREDIT,'safevision/tools/audit_v3_compact_ingress616.py'):proof[name]=sha(within(root,name))
 return dict(accepted=True,positive=records,negative=controls,identity=identity,proof_sha256=proof,default_credit_cases_preserved=4096,compact_credit_cases_added=2048,release_ready=False,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False)

def audit(root,index,repository):
 root=Path(root);require(index.get('compact_ingress_selftest')==ARCHIVE,'mandatory compact_ingress_selftest index entry missing/changed')
 folder=within(root,ARCHIVE)
 require({p.name for p in(folder/'positive').iterdir()if p.is_dir()}==set(POSITIVE),'compact positive archive incomplete/extra')
 require({p.name for p in(folder/'negative').iterdir()if p.is_dir()}=={r['mutation']for r in NEGATIVE},'compact negative archive incomplete/extra')
 result=checked_cases(root,{top:folder/'positive'/top for top in POSITIVE},{r['mutation']:folder/'negative'/r['mutation']for r in NEGATIVE},repository)
 matches=[r for r in index['positive_tests']if r['top']=='tb_v3_ingress_credit'];require(len(matches)==1,'existing credit matrix top missing/duplicated')
 credit=within(root,matches[0]['evidence']);meta=read(credit/'result.json');errors,count=normal(credit,'tb_v3_ingress_credit')
 require(count==6144==meta.get('data_comparisons'),'original matrix credit top not requalified with added compact cases')
 from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 sources(root,credit);graph(root,credit,meta)
 for p in folder.rglob('*'):
  if p.is_file():result['proof_sha256'][p.relative_to(root).as_posix()]=sha(p)
 return result

def producers(root,config,repository):
 config=read(config);root=Path(root).resolve();out=Path(config['out']).resolve()
 require(Path(config['source_root']).resolve()==root,'compact producer root changed')
 require(config.get('complete')and config.get('source_unchanged'),'compact producer set incomplete or inputs changed')
 require(config.get('allowed_cohorts')==[str(out)],'compact producers must use one exact fresh cohort')
 positive={};negative={}
 for top in POSITIVE:
  folder=Path(config['positive'][top]).resolve();require(folder==(out/'positive'/top/top).resolve(),'compact positive escaped cohort');positive[top]=folder
 for definition in NEGATIVE:
  name=definition['mutation'];folder=Path(config['negative'][name]).resolve();require(folder==(out/'negative'/name/'run'/CREDIT_TOP).resolve(),'compact negative escaped cohort');negative[name]=folder
 return checked_cases(root,positive,negative,repository)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--source-repo',type=Path);ap.add_argument('--index',type=Path);ap.add_argument('--producers',type=Path);ap.add_argument('--static-only',action='store_true');ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();repo=a.source_repo or a.repo
 try:
  if a.static_only:r=dict(accepted=False,prepared_only=True,identity=static(a.repo,repo),release_ready=False)
  elif a.producers:r=producers(a.repo,a.producers,repo)
  else:require(a.index is not None,'index required');r=audit(a.repo,read(a.index),repo)
  code=0
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e),release_ready=False);code=1
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k not in('proof_sha256','positive','negative')}));return code
if __name__=='__main__':raise SystemExit(main())
