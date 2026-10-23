"""Mandatory bytewise WAV bounds qualification; functional evidence only."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
ARCHIVE='evidence/v3/wav_pipeline_261023'
PARSER='safevision/rtl/media/v3_wav_parser_compact_ctx.v'
SOURCE='safevision/rtl/storage/v3_wav_source.v'
REF='safevision/verification/models/v3_wav_bounds_reference.sv'
ORIGIN='c085a24b7eec5a2c9d6f28df59a7385b55a1b303'
REF_SHA='b5379d89a6ec3af2e97b79aa62b9fe16dd54790e599f11fda8fb3877580e608e'
POSITIVE={
 'parser_bound_sweep':dict(top='tb_v3_wav_pipe724',suite='wav_pipe724',comparisons=1800866),
 'four_track_context':dict(top='tb_v3_wav_context730',suite='wav_context730',comparisons=2837229),
}
NEGATIVE=[
 dict(mutation='fast_round_carry_lost',target=PARSER,patch=[dict(before='carry_q<=byte_sum[8];',after="carry_q<=1'b0;")],suite='wav_pipe724',top='tb_v3_wav_pipe724',errors=[9]),
 dict(mutation='fast_greater_history_lost',target=PARSER,patch=[dict(before='greater_q<=next_greater;',after="greater_q<=1'b0;")],suite='wav_pipe724',top='tb_v3_wav_pipe724',errors=[25]),
 dict(mutation='fast_limit_offbyone',target=PARSER,patch=[dict(before="file_size-32'd8:riff_left-32'd4;",after="file_size-32'd8:riff_left-32'd3;")],suite='wav_pipe724',top='tb_v3_wav_pipe724',errors=[13]),
 dict(mutation='fast_context_not_restored',target=SOURCE,patch=[dict(before='.bound_context_in(next_context[WP_CORE_BITS+:WP_BOUND_BITS])',after=".bound_context_in(34'd0)")],suite='wav_context730',top='tb_v3_wav_context730',errors=[9]),
]
TESTS={
 'safevision/verification/unit/tb_v3_wav_pipe724.sv':'93f4d2902979828221646c0e139c608af94c754cf599f0b73d8b438a0a9bf8ae',
 # The context test and fixtures are bound by an independent authored inventory
 # plus actual compiler/input captures; a simulation figure is not hardware.
}
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def within(root,name):
 p=(Path(root)/name).resolve();assert p.is_relative_to(Path(root).resolve()),'escaped evidence path';return p
def audit(root,index,repository=None):
 root=Path(root).resolve();repository=Path(repository or root).resolve()
 assert index.get('wav_bounds_pipeline_selftest')==ARCHIVE,'missing mandatory production bytewise-bound qualification'
 assert sha(root/REF)==REF_SHA
 p=subprocess.run(['git','-C',str(repository),'show',ORIGIN+':'+REF],capture_output=True)
 assert p.returncode==0 and hashlib.sha256(p.stdout).hexdigest()==REF_SHA,'reference differs from pre-optimization Git blob'
 for n,h in TESTS.items():assert sha(root/n)==h,'independent size-sweep coverage changed'
 parser=(root/PARSER).read_text(encoding='utf-8-sig');source=(root/SOURCE).read_text(encoding='utf-8-sig')
 for marker in('parameter integer PIPELINED_BOUNDS=0','input wire[33:0] bound_context_in,output wire[33:0] bound_context_out','else if(context_load){limit_q,carry_q,greater_q}<=bound_context_in;'):
  assert parser.count(marker)==1,'legacy default/atomic sideband changed: '+marker
 for marker in('PIPELINED_WAV_BOUNDS=PREINDEXED','WP_CORE_BITS=111,WP_BOUND_BITS=34','v3_wav_parser_compact_ctx #(.PIPELINED_BOUNDS(PIPELINED_WAV_BOUNDS))','assign wp_context={wp_bound_context,wp_core_context};','.bound_context_in(next_context[WP_CORE_BITS+:WP_BOUND_BITS])'):
  assert source.count(marker)==1,'production fast-path selection/packing changed: '+marker
 assert (136+111+34+32+15)//16==20 and 4*20<128,'context/descriptor RAM overlap'
 folder=within(root,ARCHIVE);inventory=read(folder/'authored.inputs.json')
 for n,h in inventory.items():assert sha(within(root,n))==h,'authored auxiliary input changed: '+n
 sys.path.insert(0,str(root/'safevision/tools'))
 from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 proof={};records=[];controls=[]
 assert {p.name for p in(folder/'positive').iterdir()if p.is_dir()}==set(POSITIVE)
 assert {p.name for p in(folder/'negative').iterdir()if p.is_dir()}=={r['mutation']for r in NEGATIVE}
 for kind,definitions in(('positive',[dict(name=n,**row)for n,row in POSITIVE.items()]),('negative',NEGATIVE)):
  for definition in definitions:
   name=definition.get('name',definition.get('mutation'));f=folder/kind/name
   meta=read(f/('result.json'if kind=='positive'else'case.json'))
   assert meta['top']==definition['top']and meta['suite']==definition['suite']
   text=(f/'sim.log').read_text(errors='replace');errors=[int(v)for v in re.findall(r'errors\s*=\s*(\d+)',text)];counts=[int(v)for v in re.findall(r'comparisons\s*=\s*(\d+)',text)]
   assert '$finish called'in text and '[TB] '+definition['top']+' done'in text and errors and counts,'no normal DUT completion'
   assert not re.search(r'(?im)^\s*(?:\[[^]\n]+\]\s*)?(Fatal:|FATAL\b|ERROR:|SKIP\b)',text)and'[SKIP]'not in text,'tool failure/skip cannot pass'
   for n in('compile.log','compile.console.log','elab.log','elab.console.log'):
    t=(f/n).read_text(errors='replace');assert not re.search(r'(?im)^\s*(?:ERROR:|FATAL\b|Fatal:)',t)
   if kind=='positive':
    assert meta['status']=='PASS'and meta['accepted_native_runner']and meta['producer_process_exit']==0 and not meta['source_overrides']
    assert errors==[0]and counts[-1]==meta['data_comparisons']==definition['comparisons']and'[FAIL]'not in text
    source_count=sources(root,f);g=graph(root,f,meta)
   else:
    assert all(meta[k]==definition[k]for k in('mutation','target','suite','top','patch'))
    assert meta['normal_completion']and meta['detected']and meta['process_exit']==1 and errors==meta['error_counts']==definition['errors']and'[FAIL]'in text
    raw=(root/definition['target']).read_bytes();changed=raw.decode('utf-8-sig')
    for patch in definition['patch']:assert changed.count(patch['before'])==1;changed=changed.replace(patch['before'],patch['after'])
    assert meta['original_sha256']==hashlib.sha256(raw).hexdigest()and(f/'mutant.v').read_bytes()==changed.encode()and meta['mutated_sha256']==sha(f/'mutant.v')
    source_count=sources(root,f,meta);g=graph(root,f,dict(top=meta['top'],suite=meta['suite']),meta)
   item=dict(name=name,normal_completion=True,error_counts=errors,comparisons=counts[-1],source_bindings=source_count,compiler_graph=g,raw_log_sha256=sha(f/'sim.log'))
   (records if kind=='positive'else controls).append(item)
   for n in read(f/'sources.sha256.json'):
    if not n.startswith('generated:'):proof[n]=sha(within(root,n))
 for p in folder.rglob('*'):
  if p.is_file():proof[p.relative_to(root).as_posix()]=sha(p)
 for n in inventory:proof[n]=sha(root/n)
 proof['safevision/tools/audit_v3_wav_pipeline736.py']=sha(root/'safevision/tools/audit_v3_wav_pipeline736.py')
 return dict(accepted=True,positive=records,negative=controls,legacy_context_bits=111,additional_context_bits=34,production_context_words_per_track=20,reference_origin_commit=ORIGIN,proof_sha256=proof,release_ready=False,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False)
