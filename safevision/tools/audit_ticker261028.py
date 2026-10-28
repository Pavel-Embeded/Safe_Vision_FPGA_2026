"""Independent current-source replay of all preserved and added HDL checks.

The historical matrix and frozen references are read as originally published.
This extension never replaces their inventories or original routed evidence.
"""
import argparse,hashlib,json,re,sys,subprocess
from pathlib import Path
from audit_v3_raw_logs import audit_file
from check_v3_sim_graph import check as graph
from v3_sources import snapshot,FLOW
ROOT=Path(__file__).resolve().parents[2]
def read(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise ValueError(message)
def bind(root,folder,target=None,mutant_sha=None):
 hashes=read(folder/'sources.sha256.json')
 for name,digest in hashes.items():
  if name.startswith('generated:'):
   p=(folder/name[10:]).resolve();require(p.is_relative_to(folder.resolve()),'runtime path escape')
   require(sha(p)==digest,'runtime bytes changed: '+name)
  elif name==target:require(digest==mutant_sha,'mutant capture differs')
  else:
   p=(root/name).resolve();require(p.is_relative_to(root.resolve()),'source path escape')
   require(sha(p)==digest,'source input differs from current files: '+name)
 return len(hashes)
def audit(root,regression,ticker,board,controls):
 matrix=read(root/'safevision/build/qualification/four_features_261020.json')
 original=json.loads(subprocess.check_output(['git','-C',str(root),'cat-file','blob','09faac2e8fa718c9f92ef4a5013b68003ec8afe6:safevision/build/qualification/four_features_261020.json']))
 require(matrix==original,'historical matrix or frozen references were rebased')
 require(len(matrix['positive'])==303 and len(matrix['negative'])==221,'preserved inventory changed')
 sources=snapshot(root);old=matrix['physical_source_sha256']
 allowed={str(FLOW/n).replace('\\','/')for n in ('base/safevision_v3_base.al','hd/safevision_v3_hd.al','v3_board_assets.list','v3_board_sources.list','v3_board_sources_hd.list','v3_build_parameters_base.tcl')}
 allowed|={'safevision/tools/check_v3_rom_netlist.py','safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v','safevision/rtl/storage/sd_bmp_player.v'}
 top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text('utf-8-sig')
 require('.MESSAGE_CHARS(32)'in top and '.WIDTH(HDMI_STATUS_W)'in top and '.PIXEL_LATENCY(5),.SOURCE_AHEAD(5),.CLIP_INPUT(0)'in top and 'b_query_group0 <= b_query_packed'in top and 'cmd_value==101||cmd_value==102'not in top,'current32/shared-status/lookahead/packed-reply production profile differs')
 require('.REGISTERED_RESIDENT_READY(TICKER_ENABLE)'in top,'resident readiness profile not selected by the production flag')
 new={'safevision/rtl/video/v3_scrolling_ticker.v','safevision/assets/fonts/v3_ticker16.mem','safevision/assets/fonts/v3_ticker16.provenance.json'}|{str(FLOW/n).replace('\\','/')for n in ('ticker_enable.v','base/v3_ticker16.mem','hd/v3_ticker16.mem')}
 require(set(old)<=set(sources)and set(sources)-set(old)==new,'unreviewed production dependency added/removed')
 changes={n for n,h in old.items()if sources[n]!=h}
 optional={str(FLOW/'v3_build_parameters_base.tcl').replace('\\','/')}
 require((allowed-optional)<=changes and changes<=allowed,'unexpected physical changes: '+repr((changes-allowed)|((allowed-optional)-changes)))
 require(len(sources)==212,'current physical inventory changed')
 summary=read(regression/'summary.json');require(summary.get('complete')and summary.get('accepted'),'full native campaign incomplete/failed')
 expected_jobs={('legacy','a'),('legacy','b')}|{('positive',r['top'])for r in matrix['positive']if not r['legacy']}|{('negative',r['mutation'])for r in matrix['negative']}
 require({(r['kind'],r['name'])for r in summary['records']}==expected_jobs,'native campaign inventory differs')
 checked=[]
 for case in matrix['positive']:
  top=case['top'];suite=case['suite']
  if case['legacy']:
   key='a'if suite=='legacy_a'else'b';base=regression/'legacy'/key/'native'
   record=read(base/'results.json');require(record['complete']and record['source_unchanged']and record['process_exit']==0,'legacy campaign failed')
   bind(root,base)
   log=base/'native'/top/'xsim.log'if key=='a'else base/'native'/(top+'_sim.log')
   raw=audit_file(log);require(raw['accepted'],'legacy raw failure: '+top)
  else:
   base=regression/'positive'/top;record=read(base/'result.json');require(record['status']=='PASS'and record['process_exit']==0,'positive native failure: '+top)
   folder=base/'native'/top;bind(root,folder);raw=audit_file(folder/'sim.log',True);require(raw['accepted'],'positive raw failure: '+top)
   graph(root,folder,dict(suite=suite,top=top))
  checked.append(dict(top=top,suite=suite,raw_sha256=raw['sha256']))
 negatives=[]
 for case in matrix['negative']:
  folder=regression/'negative'/case['mutation'];record=read(folder/'result.json')
  require(record['case']==case and record['status']=='PASS'and record['process_exit']==1 and record['normal_completion'],'negative case not an HDL detection')
  path=root/case['target'];require(sha(path)==record['original_sha256'],'negative original changed')
  text=path.read_text('utf-8-sig')
  for patch in case['patch']:
   require(text.count(patch['before'])==patch.get('occurrences',1),'negative patch count changed')
   text=text.replace(patch['before'],patch['after'])
  mutant=folder/'mutant.v';require(text==mutant.read_text('utf-8-sig')and sha(mutant)==record['mutated_sha256'],'negative mutant differs')
  native=folder/'native'/case['top'];bind(root,native,case['target'],record['mutated_sha256']);graph(root,native,dict(suite=case['suite'],top=case['top']),record)
  log=(native/'sim.log').read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',log)]
  require('$finish called'in log and'[FAIL'in log and bool(re.search(r'PASS\s+'+re.escape(case['top'])+r'\b|\[TB\]\s*'+re.escape(case['top'])+r'\s+done',log)),'negative completion/detector absent')
  require(counts==record['error_counts']and any(counts),'negative errors absent')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log)and'[SKIP]'not in log,'negative tool failure or skip')
  negatives.append(dict(name=case['mutation'],raw_sha256=sha(native/'sim.log')))
 additions=[]
 for suite,top,base in (('ticker261028','tb_v3_ticker_clip',ticker),('ticker261028','tb_v3_ticker_base',ticker),('ticker_board261028','tb_v3_ticker_board',board)):
  record=read(base/'results.json');require(record['complete'],'new positive suite incomplete')
  native=base/top;bind(root,native);raw=audit_file(native/'sim.log',True);require(raw['accepted'],'new positive raw failure')
  g=graph(root,native,dict(suite=suite,top=top));additions.append(dict(top=top,raw_sha256=raw['sha256'],compiler=g))
 control_summary=read(controls/'summary.json');require(control_summary['accepted']and len(control_summary['cases'])==15,'ticker controls incomplete')
 wanted={'frozen_phase','pixel_advance','early_wrap','mirrored_columns','one_clock_misalignment','overwrites_uptime','corrupted_rom_bit','wrong_production_id','bypassed_overlay','wrong_status_signature','media_reset_leaks','wrong_lookahead','premature_input_clip','packed_query_bank1_lost','packed_query_bank4_lost'}
 require({c['name']for c in control_summary['cases']}==wanted,'ticker control inventory changed')
 for case in control_summary['cases']:
  require(case['accepted']and case['process_exit']==1 and case['normal_completion'],'ticker control did not finish normally')
  folder=controls/case['name'];p=root/case['target'];require(sha(p)==case['original_sha256'],'ticker control source changed')
  text=p.read_text('utf-8-sig');require(text.count(case['before'])==1,'ticker control patch changed')
  require((folder/'mutant.v').read_text('utf-8-sig')==text.replace(case['before'],case['after'])and sha(folder/'mutant.v')==case['mutated_sha256'],'ticker control mutant changed')
  top='tb_v3_ticker_board'if'safevision_top/'in case['target']else'tb_v3_ticker_clip';suite='ticker_board261028'if top.endswith('board')else'ticker261028'
  native=folder/'native'/top;bind(root,native,case['target'],case['mutated_sha256']);graph(root,native,dict(suite=suite,top=top),case)
  log=(native/'sim.log').read_text('utf-8',errors='replace')
  require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in log and'PASS '+top in log and'[FAIL]'in log and any(case['error_counts']),'ticker detector raw evidence changed')
 # The resident handoff is terminal until media reset. Compare every public
 # player output against the unchanged original, including arbitrary contexts.
 resident=controls.parent/'resident';resident_controls=controls.parent/'resident_controls'
 rtop='tb_v3_resident_owner_equivalence';rsuite='resident_owner_equivalence261028'
 require(read(resident/'results.json')['complete'],'resident equivalence incomplete')
 native=resident/rtop;bind(root,native);raw=audit_file(native/'sim.log',True)
 require(raw['accepted'],'resident public-interface equivalence failed')
 additions.append(dict(top=rtop,raw_sha256=raw['sha256'],compiler=graph(root,native,dict(suite=rsuite,top=rtop))))
 rows=read(resident_controls/'summary.json');require(rows['accepted']and len(rows['cases'])==2,'resident error controls incomplete')
 require({c['name']for c in rows['cases']}=={'resident_gap_bypassed','resident_owner_bypassed'},'resident detector inventory differs')
 for case in rows['cases']:
  require(case['accepted']and case['process_exit']==1 and case['normal_completion'],'resident detector did not finish normally')
  folder=resident_controls/case['name'];path=root/case['target'];require(sha(path)==case['original_sha256'],'resident source changed')
  text=path.read_text('utf-8-sig');require(text.count(case['before'])==1,'resident detector patch differs')
  require((folder/'mutant.v').read_text('utf-8-sig')==text.replace(case['before'],case['after'])and sha(folder/'mutant.v')==case['mutated_sha256'],'resident mutant differs')
  native=folder/'native'/rtop;bind(root,native,case['target'],case['mutated_sha256']);graph(root,native,dict(suite=rsuite,top=rtop),case)
  log=(native/'sim.log').read_text('utf-8',errors='replace')
  require(sha(native/'sim.log')==case['sim_sha256']and'$finish called'in log and'[TB] '+rtop+' done'in log and'[FAIL]'in log and any(case['error_counts']),'resident raw detector missing')
  require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',log),'resident control crashed or skipped')
 return dict(accepted=True,physical_inputs=212,production_changes=sorted(changes),production_additions=sorted(new),preserved_positive_tops=303,added_positive_tops=4,total_positive_tops=307,preserved_semantic_controls=221,added_semantic_controls=17,total_semantic_controls=238,positive=checked,negative=negatives,additions=additions,source_sha256=sources,fresh_native_simulation=True,hardware_verified=False)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT)
 for key in ('regression','ticker','board','controls','output'):ap.add_argument('--'+key,type=Path,required=True)
 a=ap.parse_args()
 try:result=audit(a.repo.resolve(),a.regression,a.ticker,a.board,a.controls)
 except Exception as exc:result=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(result,indent=2)+'\n','utf-8');print('TICKER FUNCTIONAL AUDIT '+('PASS'if result['accepted']else'FAILED: '+result['error']))
 return 0 if result['accepted']else 1
if __name__=='__main__':sys.exit(main())
