"""Require atomic SDRAM observation, cache retiming and exact BMP geometry proof."""
from pathlib import Path
import hashlib,json,re,sys
ARCHIVE='evidence/v3/pipeline_261023'
POSITIVE={'tb_v3_guard_stage804':('guard_stage804',1807),'tb_v3_cache_pipe805':('cache_pipe805',30505),'tb_v3_base_cache_miter188':('base_cache_miter188',30350),'tb_v3_normalizer_miter203':('normalizer_miter203',64403817),'tb_v3_flexible_bmp542':('flexible_bmp542',6876935),'tb_v3_flexible_fs550':('flexible_fs550',614400),'tb_v3_board_clocks':('v3_board_clocks',195),'tb_v3_handbook_video_base':('handbook_video',3686400)}
TOP='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
NEGATIVE=[dict(mutation='guard_payload_misaligned',target=TOP,suite='guard_stage804',top='tb_v3_guard_stage804',before='guard_write_data_q<=mem_wdata;',after='guard_write_data_q<=mem_addr;',errors=[878]),dict(mutation='guard_valid_bypasses_stage',target=TOP,suite='guard_stage804',top='tb_v3_guard_stage804',before='.accepted(guard_accept_q),.write_addr(guard_write_addr_q)',after='.accepted(writer_accepted),.write_addr(guard_write_addr_q)',errors=[236]),dict(mutation='cache_crc_bypassed',target='safevision/rtl/video/v3_line_cache.v',suite='cache_pipe805',top='tb_v3_cache_pipe805',before='wire final_crc_mismatch=(crc^cache_rdata)!=expected;',after="wire final_crc_mismatch=1'b0;",errors=[17155]),dict(mutation='geometry_equal_case_lost',target='safevision/rtl/media/v3_bmp_normalizer.v',suite='flexible_bmp542',top='tb_v3_flexible_bmp542',before='geometry_ge_q<=geometry_scratch>=geometry_divisor;',after='geometry_ge_q<=geometry_scratch>geometry_divisor;',errors=[386400])]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def within(root,n):
 p=(root/n).resolve();assert p.is_relative_to(root),'escaped proof input';return p
def audit(root,index,repository=None):
 root=Path(root).resolve();assert index.get('pipeline_selftest')==ARCHIVE,'missing mandatory retiming proof';folder=root/ARCHIVE
 authored=read(folder/'authored.inputs.json');assert authored
 for n,h in authored.items():assert sha(within(root,n))==h,'changed independent test input: '+n
 sys.path.insert(0,str(root/'safevision/tools'));from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 proof={};positive=[];negative=[]
 assert {p.name for p in(folder/'positive').iterdir()if p.is_dir()}==set(POSITIVE)
 assert {p.name for p in(folder/'negative').iterdir()if p.is_dir()}=={r['mutation']for r in NEGATIVE}
 for kind,defs in [('positive',[dict(name=n,suite=v[0],top=n,comparisons=v[1])for n,v in POSITIVE.items()]),('negative',NEGATIVE)]:
  for row in defs:
   name=row.get('name',row.get('mutation'));f=folder/kind/name;meta=read(f/('result.json'if kind=='positive'else'case.json'));assert meta['top']==row['top']and meta['suite']==row['suite']
   text=(f/'sim.log').read_text(errors='replace');errors=[int(x)for x in re.findall(r'errors\s*=\s*(\d+)',text)];counts=[int(x)for x in re.findall(r'comparisons\s*=\s*(\d+)',text)]
   marker=re.search(r'PASS\s+'+re.escape(row['top'])+r'\b|\[TB\]\s*'+re.escape(row['top'])+r'\s+done',text)
   assert '$finish called'in text and marker and errors and counts,'missing normal completion'
   assert not re.search(r'(?im)^\s*(?:\[[^]\n]+\]\s*)?(ERROR:|Fatal:|FATAL\b|SKIP\b)',text)and'[SKIP]'not in text
   for n in('compile.log','compile.console.log','elab.log','elab.console.log'):assert not re.search(r'(?im)^\s*(ERROR:|Fatal:|FATAL\b)',(f/n).read_text(errors='replace'))
   if kind=='positive':
    assert meta['status']=='PASS'and meta['accepted_native_runner']and meta['producer_process_exit']==0 and not meta['source_overrides']
    assert errors and not any(errors)and counts[-1]==meta['data_comparisons']==row['comparisons']and'[FAIL]'not in text
    count=sources(root,f);g=graph(root,f,meta)
   else:
    assert all(meta[k]==row[k]for k in('mutation','target','suite','top'))and meta['patch']==[dict(before=row['before'],after=row['after'])]
    assert meta['process_exit']==1 and meta['normal_completion']and meta['detected']and errors==meta['error_counts']==row['errors']and'[FAIL]'in text
    raw=(root/row['target']).read_bytes();v=raw.decode('utf-8-sig');assert v.count(row['before'])==1 and meta['original_sha256']==hashlib.sha256(raw).hexdigest()
    assert(f/'mutant.v').read_bytes()==v.replace(row['before'],row['after']).encode()and meta['mutated_sha256']==sha(f/'mutant.v')
    count=sources(root,f,meta);g=graph(root,f,dict(top=row['top'],suite=row['suite']),meta)
   (positive if kind=='positive'else negative).append(dict(name=name,top=row['top'],comparisons=counts[-1],error_counts=errors,source_bindings=count,compiler_graph=g,raw_log_sha256=sha(f/'sim.log')))
   for n in read(f/'sources.sha256.json'):
    if not n.startswith('generated:'):proof[n]=sha(within(root,n))
 for p in folder.rglob('*'):
  if p.is_file():proof[p.relative_to(root).as_posix()]=sha(p)
 for n in authored:proof[n]=sha(root/n)
 n='safevision/tools/audit_v3_pipeline815.py';proof[n]=sha(root/n)
 return dict(accepted=True,positive=positive,negative=negative,proof_sha256=proof,release_ready=False,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False)
