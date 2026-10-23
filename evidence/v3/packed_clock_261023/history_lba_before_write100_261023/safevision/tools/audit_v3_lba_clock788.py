"""Mandatory current-source address and actual-control-clock integration proof.

Clock models prove wiring/time units, not silicon PLL behavior. Routed STA and
bitstream/hardware approval remain separate, mandatory release steps.
"""
from pathlib import Path
import hashlib,json,re,sys
ARCHIVE='evidence/v3/lba_control_clock_261023'
TOP='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
FS='safevision/rtl/storage/v3_shared_fs_service.v'
POSITIVE={
 'lba_public_contract':dict(suite='lba_pipeline747',top='tb_v3_lba_pipeline747',comparisons=28673),
 'lba_wait_timeout':dict(suite='lba_timeout759',top='tb_v3_lba_timeout759',comparisons=521),
 'control_clock':dict(suite='control_clock776',top='tb_v3_control_clock776',comparisons=30),
 'board_clocks':dict(suite='v3_board_clocks',top='tb_v3_board_clocks',comparisons=195),
}
NEGATIVE=[
 dict(mutation='lba_product_spc_lost',target=FS,suite='lba_pipeline747',top='tb_v3_lba_pipeline747',before='product_q<=shared_cluster*sec_per_clus;',after="product_q<=shared_cluster*8'd1;",errors=[2047]),
 dict(mutation='lba_file_valid_unqualified',target=FS,suite='lba_pipeline747',top='tb_v3_lba_pipeline747',before='.external_lba_valid(file_lba_valid)',after=".external_lba_valid(1'b1)",errors=[8184]),
 dict(mutation='lba_result_valid_lost',target=FS,suite='lba_pipeline747',top='tb_v3_lba_pipeline747',before='valid2<=valid1;',after="valid2<=1'b0;",errors=[4096]),
 dict(mutation='lba_owner_tag_inverted',target=FS,suite='lba_pipeline747',top='tb_v3_lba_pipeline747',before='assign file_lba_valid=valid2&&!owner2;',after='assign file_lba_valid=valid2&&owner2;',errors=[4096]),
 dict(mutation='wrong_UART',target=TOP,suite='control_clock776',top='tb_v3_control_clock776',before='v3_uart_link #(.CLK_HZ(SYS_HZ),',after='v3_uart_link #(.CLK_HZ(100000000),',errors=[3]),
 dict(mutation='wrong_frame',target=TOP,suite='control_clock776',top='tb_v3_control_clock776',before='.FRAME_CYCLES(SYS_HZ/10)',after='.FRAME_CYCLES(10000000)',errors=[1]),
 dict(mutation='wrong_actual_SYS',target=TOP,suite='control_clock776',top='tb_v3_control_clock776',before='assign sys_clk=HD?pll_sys100_clk:mem_clk;',after='assign sys_clk=pll_sys100_clk;',errors=[5]),
]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def within(root,n):
 p=(root/n).resolve();assert p.is_relative_to(root),'escaped proof path';return p
def audit(root,index,repository=None):
 root=Path(root).resolve();assert index.get('lba_control_clock_selftest')==ARCHIVE,'missing address/clock integration evidence'
 folder=root/ARCHIVE;inventory=read(folder/'authored.inputs.json')
 for n,h in inventory.items():assert sha(within(root,n))==h,'changed authored test input: '+n
 sys.path.insert(0,str(root/'safevision/tools'))
 from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 from check_v3_clock_contract import check as clocks
 from check_v3_command_catalog import check as catalog
 assert clocks(root)['complete']and catalog(root)['accepted']
 proof={};positive=[];negative=[]
 assert {p.name for p in(folder/'positive').iterdir()if p.is_dir()}==set(POSITIVE)
 assert {p.name for p in(folder/'negative').iterdir()if p.is_dir()}=={r['mutation']for r in NEGATIVE}
 for kind,definitions in [('positive',[dict(name=n,**row)for n,row in POSITIVE.items()]),('negative',NEGATIVE)]:
  for row in definitions:
   name=row.get('name',row.get('mutation'));f=folder/kind/name;meta=read(f/('result.json'if kind=='positive'else'case.json'))
   assert meta['top']==row['top']and meta['suite']==row['suite']
   text=(f/'sim.log').read_text(errors='replace');errors=[int(x)for x in re.findall(r'errors\s*=\s*(\d+)',text)];counts=[int(x)for x in re.findall(r'comparisons\s*=\s*(\d+)',text)]
   assert '$finish called'in text and '[TB] '+row['top']+' done'in text and errors and counts,'no normal completion'
   assert not re.search(r'(?im)^\s*(?:\[[^]\n]+\]\s*)?(ERROR:|Fatal:|FATAL\b|SKIP\b)',text)and'[SKIP]'not in text
   for n in('compile.log','compile.console.log','elab.log','elab.console.log'):
    assert not re.search(r'(?im)^\s*(ERROR:|Fatal:|FATAL\b)',(f/n).read_text(errors='replace'))
   if kind=='positive':
    assert meta['status']=='PASS'and meta['accepted_native_runner']and meta['producer_process_exit']==0 and not meta['source_overrides']
    assert errors==[0]and counts[-1]==meta['data_comparisons']==row['comparisons']and'[FAIL]'not in text
    count=sources(root,f);g=graph(root,f,meta)
   else:
    assert all(meta[k]==row[k]for k in('mutation','target','suite','top'))
    assert meta['patch']==[dict(before=row['before'],after=row['after'])]
    assert meta['normal_completion']and meta['detected']and meta['process_exit']==1 and errors==meta['error_counts']==row['errors']and'[FAIL]'in text
    raw=(root/row['target']).read_bytes();v=raw.decode('utf-8-sig');assert v.count(row['before'])==1
    assert meta['original_sha256']==hashlib.sha256(raw).hexdigest()and(f/'mutant.v').read_bytes()==v.replace(row['before'],row['after']).encode()and meta['mutated_sha256']==sha(f/'mutant.v')
    count=sources(root,f,meta);g=graph(root,f,dict(top=row['top'],suite=row['suite']),meta)
   item=dict(name=name,top=row['top'],suite=row['suite'],source_bindings=count,compiler_graph=g,error_counts=errors,comparisons=counts[-1],raw_log_sha256=sha(f/'sim.log'))
   (positive if kind=='positive'else negative).append(item)
   for n in read(f/'sources.sha256.json'):
    if not n.startswith('generated:'):proof[n]=sha(within(root,n))
 # Replay every static fixture using the current strict checkers. Fixtures are
 # frozen by an authored inventory; a previously written success is insufficient.
 cases=read(folder/'static/spec.json');assert len(cases)==17 and sum(bool(r['positive'])for r in cases)==2
 for row in cases:
  r=folder/'static'/row['name']
  try:c=catalog(r);k=clocks(r)
  except ValueError:assert not row['positive'],'valid clock fixture rejected'
  else:assert row['positive']and c['accepted']and k['complete'],'invalid clock fixture accepted'
 for p in folder.rglob('*'):
  if p.is_file():proof[p.relative_to(root).as_posix()]=sha(p)
 for n in inventory:proof[n]=sha(root/n)
 n='safevision/tools/audit_v3_lba_clock788.py';proof[n]=sha(root/n)
 return dict(accepted=True,positive=positive,negative=negative,static_positive=2,static_negative=15,proof_sha256=proof,clock_model_is_not_silicon=True,release_ready=False,routed_sta_passed=False,bitstreams_verified=False,hardware_verified=False)
