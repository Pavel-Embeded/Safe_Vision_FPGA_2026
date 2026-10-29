
import argparse,hashlib,json,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--run-dir',required=True);ap.add_argument('--case',action='append');a=ap.parse_args()
 out=Path(a.run_dir).resolve();out.mkdir(parents=True,exist_ok=True)
 if not str(out).isascii():raise ValueError('ASCII work directory required')
 compact='v3_wav_parser_compact_ctx wp(' in (ROOT/'safevision/rtl/storage/v3_wav_source.v').read_text(encoding='utf-8')
 parser='safevision/rtl/media/v3_wav_parser_compact_ctx.v' if compact else 'safevision/rtl/media/v3_wav_parser_ctx.v'
 swap=('assign sample=word;','assign sample={word[15:0],word[31:16]};') if compact else ('sample     <= {din, r_lo, l_hi, l_lo};','sample     <= {l_hi, l_lo, din, r_lo};')
 cases=[
  ('generation_tag','safevision/rtl/audio/v3_pcm_ring.v','out_data<={generation,rdata}',"out_data<={generation^8'h01,rdata}",'tb_v3_audio_negative_generation','[FAIL AUDIO_GENERATION]'),
  ('swap_stereo',parser,*swap,'tb_v3_audio_negative_stereo','[FAIL AUDIO_STEREO]'),
  ('erase_hop_context','safevision/rtl/storage/v3_cluster_walker_ctx.v','if(context_load)begin hop_cnt<=context_hop;','if(context_load)begin hop_cnt<=0;','tb_v3_audio_negative_hop','[FAIL AUDIO_HOP_CONTEXT]')]
 if compact:cases.extend([
  ('container_stereo',parser,*swap,'tb_v3_audio_negative_container','[FAIL AUDIO_CONTAINER_PCM] case=0 '),
  ('container_bound',parser,"if(padded_end>{2'd0,riff_left})reject_now=1;","if(1'b0)reject_now=1;",'tb_v3_audio_negative_container','[FAIL AUDIO_CONTAINER_PCM] case=169 '),
  ('container_extension',parser,'left<=assembled;pad<=assembled[0];index<=0;',"left<=(kind==K_FMT&&assembled>16)?32'd16:assembled;pad<=assembled[0];index<=0;",'tb_v3_audio_negative_container','[FAIL AUDIO_CONTAINER_END] case=1 ')])
 selected=[c for c in cases if not a.case or c[0] in a.case]
 if a.case and set(a.case)-{c[0] for c in cases}:raise ValueError('unknown or inactive parser mutation')
 before_script=sha(Path(__file__));records=[];originals={}
 for name,relative,old,new,top,marker in selected:
  source=ROOT/relative;raw=source.read_bytes();originals[relative]=sha(source);text=raw.decode('utf-8-sig')
  expected_anchors=2 if name=='generation_tag' else 1
  if text.count(old)!=expected_anchors:raise RuntimeError('mutation anchor ambiguous: '+name)
  folder=out/name;folder.mkdir(exist_ok=True);mutant=folder/source.name;mutant.write_text(text.replace(old,new),encoding='utf-8');mutated_hash=sha(mutant)
  suite='wav_container_negative' if top=='tb_v3_audio_negative_container' else 'audio_negative'
  m=json.loads((ROOT/f'safevision/build/manifests/{suite}_sim.json').read_text())
  command=[sys.executable,str(ROOT/'safevision/tools/run_v3_shared_storage.py'),'--suite',suite,'--run-dir',str(folder/'simulation'),'--top',top,'--override-source',relative+'='+str(mutant)]
  with(folder/'console.log').open('w',encoding='utf-8') as f:p=subprocess.run(command,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,timeout=300)
  runfolder=folder/'simulation'/top;sim=runfolder/'sim.log';log=sim.read_text(encoding='utf-8',errors='replace') if sim.exists() else ''
  completion='$finish called' in log and bool(re.search(r'PASS\s+'+re.escape(top)+r'\s+errors=',log))
  tool_failure=bool(re.search(r'(?im)^\s*(Fatal:|FATAL\b|ERROR:)',log));errors=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',log)]
  native_done=False;child=folder/'simulation/results.json'
  if child.exists():
   child_data=json.loads(child.read_text());native_done=bool(child_data.get('results')) and child_data['results'][0].get('error','').startswith('missing completion/checks or nonzero error:')
  identity_file=runfolder/'sources.sha256.json';preserved=False;identity_before={};identity_after={}
  if identity_file.exists():
   identity_before=json.loads(identity_file.read_text());identity_after={key:sha(mutant if key==relative else runfolder/key.split(':',1)[1] if key.startswith('generated:') else ROOT/key) for key in identity_before};preserved=identity_before==identity_after
  runtime_assets={name:sha(runfolder/Path(name).name)==sha(ROOT/name) for name in m.get('assets',[]) if (runfolder/Path(name).name).exists()}
  assets_ok=len(runtime_assets)==len(m.get('assets',[])) and all(runtime_assets.values())
  detected=p.returncode==1 and native_done and completion and not tool_failure and marker in log and any(errors) and preserved and assets_ok and sha(mutant)==mutated_hash
  record={'mutation':name,'top':top,'detected':detected,'normal_completion':completion,'native_stages_completed':native_done,'tool_failure':tool_failure,'required_marker':marker,'error_counts':errors,'original_sha256':originals[relative],'mutated_sha256':mutated_hash,'source_before_sha256':identity_before,'source_after_sha256':identity_after,'runtime_static_assets_match':runtime_assets,'source_unchanged':preserved}
  records.append(record);print(json.dumps({k:v for k,v in record.items() if k not in ('source_before_sha256','source_after_sha256')}),flush=True)
  (out/'negative_controls.json').write_text(json.dumps({'complete':False,'cases':records},indent=2))
 preserved=all(sha(ROOT/key)==value for key,value in originals.items()) and sha(Path(__file__))==before_script
 result={'active_parser':'compact111' if compact else 'legacy445','cases':records,'originals_preserved':preserved,'runner_sha256':before_script,'complete':preserved and len(records)==len(selected) and all(x['detected'] for x in records),'hardware_verified':False}
 (out/'negative_controls.json').write_text(json.dumps(result,indent=2));return 0 if result['complete'] else 1
if __name__=='__main__':sys.exit(main())
