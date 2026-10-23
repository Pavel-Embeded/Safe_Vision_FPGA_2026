"""Qualify a clock-stimulus correction without rebasing any frozen oracle.

The original134-reference map and all original Git blobs remain mandatory.
Only the current clock stimulus has a separate, exact byte transformation.
This module is nonphysical and never approves bitgen, STA or hardware.
"""
from pathlib import Path
import hashlib,json,re,subprocess

TARGET='safevision/verification/models/v3_memory_pll_clock_model.sv'
MATRIX='safevision/build/qualification/four_features_261020.json'
COMMIT='c6a6549871d97755708120d2a76239011cef94bb'
OLD_SHA='d0ad18b9a432c74002cf87356d4a629783b110ec4d7dbbd8dfd3781e9986c6bd'
NEW_SHA='cd9669c84ba0798fbf2a840a2eadd2637a5a081b765f29c993ea177e8af8ea92'
OLD_LINE=b' reg sys=0,mem=0;always #5 sys=~sys;always #10 mem=~mem;\n'
NEW_LINE=b' reg sys=1,mem=0;always #5 sys=~sys;always #10 mem=~mem;\n'
COMMENT=b' // Align the 100/50 MHz rising edges as the phase-0 production PLL does.\n'
FOLDER='evidence/v3/clock_stimulus_261023'
ARCHIVE='original/v3_memory_pll_clock_model.sv'

def require(ok,message):
 if not ok:raise ValueError('qualified clock stimulus: '+message)
def digest(raw):return hashlib.sha256(raw).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def inside(root,name):
 p=(root/name).resolve();require(not Path(name).is_absolute()and p.is_relative_to(root.resolve())and p.is_file(),'missing/escaping proof '+name);return p
def metadata():
 return dict(schema=1,stimulus_path=TARGET,source_matrix_path=MATRIX,original_repository_path=TARGET,
  original_source_commit=COMMIT,original_sha256=OLD_SHA,current_sha256=NEW_SHA,original_archive=ARCHIVE,
  transformations=[dict(operation='replace_exact_once',before=OLD_LINE.decode(),after=NEW_LINE.decode()),
   dict(operation='insert_exact_once_before',anchor=NEW_LINE.decode(),insert=COMMENT.decode()),
   dict(operation='convert_all_LF_to_CRLF',reject_existing_CR=True)],
  original_frozen_reference_count=134,oracle_sha_or_inventory_rebased=False,
  required_board_clock_comparisons=219,required_focused_positive=3,required_focused_refusals=24,
  required_bus_hfn_positive=3,required_bus_hfn_refusals=14,
  rationale='Original sys=0 puts WRITE100 rising5ns away from MEM50. Current sys=1 models the phase0 rising-edge contract checked against real native PLL pin ownership. This is stimulus qualification, not an oracle edit.')
def transformed(original):
 require(digest(original)==OLD_SHA,'original clock Git bytes/SHA changed')
 require(b'\r'not in original and original.count(OLD_LINE)==1 and COMMENT not in original,'original LF/unique replacement contract changed')
 changed=original.replace(OLD_LINE,NEW_LINE)
 require(changed.count(NEW_LINE)==1,'replacement anchor is not unique')
 changed=changed.replace(NEW_LINE,COMMENT+NEW_LINE)
 changed=changed.replace(b'\n',b'\r\n')
 require(digest(changed)==NEW_SHA,'declared exact transformation no longer reproduces compiled stimulus')
 return changed
def verify_core(frozen,git_frozen,git_blobs,current,archived,meta):
 require(meta==metadata(),'qualification metadata/allowed transformation changed')
 require(len(frozen)==134 and frozen==git_frozen,'entire134 original reference inventory differs from original Git matrix')
 require(frozen.get(TARGET)==OLD_SHA,'original oracle SHA was rebased or removed')
 require(set(git_blobs)==set(current)==set(frozen),'original/reference input set is incomplete')
 require(archived==git_blobs[TARGET]and digest(archived)==OLD_SHA,'archived original is not the untouched original Git blob')
 replacement=transformed(archived)
 for name,wanted in frozen.items():
  require(digest(git_blobs[name])==wanted,'original Git oracle changed: '+name)
  require((archived if name==TARGET else current[name])==git_blobs[name],'original frozen reference changed: '+name)
  if name!=TARGET:require(digest(current[name])==wanted,'current independent oracle changed: '+name)
 require(current[TARGET]==replacement and digest(current[TARGET])==NEW_SHA,'current stimulus is not the exact qualified transformation')
 return dict(accepted=True,original_references_checked=134,unchanged_current_oracles=133,
  archived_original_sha256=OLD_SHA,current_stimulus_sha256=NEW_SHA,oracle_sha_or_inventory_rebased=False)
def git_blobs(repository,names):
 names=sorted(names);p=subprocess.run(['git','-C',str(repository),'cat-file','--batch'],input=''.join(COMMIT+':'+n+'\n'for n in names).encode(),capture_output=True)
 require(p.returncode==0,'original Git object read failed');out={};offset=0
 for name in names:
  end=p.stdout.index(b'\n',offset);head=p.stdout[offset:end].split();require(len(head)==3 and head[1]==b'blob','missing original Git blob '+name)
  size=int(head[2]);offset=end+1;out[name]=p.stdout[offset:offset+size];offset+=size;require(p.stdout[offset:offset+1]==b'\n','invalid Git blob delimiter');offset+=1
 require(offset==len(p.stdout),'extra original Git object output');return out
def capture_input_contract(before,after):
 require(before.get(TARGET)==NEW_SHA,'actual selected capture compiled a different clock stimulus')
 # The original run_v3_sim API recorded its precompile input set. A missing
 # after file is not fabricated, inferred, or renamed into an old capture.
 if after is None:return False
 require(after==before,'actual recorded post-run input set differs')
 return True
def audit(root,repository,index,matrix):
 root,repository=Path(root).resolve(),Path(repository).resolve()
 require(index.get('clock_stimulus_qualification_schema')==1,'explicit qualified-stimulus schema is required')
 require(index.get('clock_stimulus_qualification')==FOLDER,'qualification proof path changed')
 require(index['matrix']==MATRIX and matrix['source_build_commit']==COMMIT,'qualification original matrix/commit changed')
 folder=(root/FOLDER).resolve();require(folder.is_relative_to(root),'qualification folder escaped project')
 meta_path=inside(folder,'qualification.json');archive_path=inside(folder,ARCHIVE)
 frozen=matrix['frozen_reference_sha256'];original=git_blobs(repository,list(frozen)+[MATRIX]);git_matrix=read_bytes_json(original.pop(MATRIX))
 result=verify_core(frozen,git_matrix['frozen_reference_sha256'],original,{n:inside(root,n).read_bytes()for n in frozen},archive_path.read_bytes(),read(meta_path))
 from audit_v3_resource_checkpoint import sources
 from check_v3_sim_graph import check as graph
 from audit_v3_raw_logs import audit_file
 clock_rows=[r for r in index['positive_tests']if r['top']=='tb_v3_board_clocks'];require(len(clock_rows)==1,'one actual production board-clock test is required')
 row=clock_rows[0];capture=inside(root,row['evidence']+'/result.json').parent;actual=read(capture/'result.json')
 require(actual['status']=='PASS'and actual['data_comparisons']==219 and actual['accepted_native_runner']and actual.get('producer_process_exit')==0,'actual board-clock positive must finish normally219/0')
 require(digest((capture/'result.json').read_bytes())==row['result_sha256'],'board clock producer metadata changed')
 require(sources(root,capture)>0 and graph(root,capture,actual)['accepted']and audit_file(capture/'sim.log',True)['accepted'],'board clock actual compiled/raw evidence failed')
 selected=[];post_count=0
 for kind,row in [('positive',r)for r in index['positive_tests']]+[('negative',r)for r in index['negative_controls']]:
  before=read(inside(root,row['evidence']+'/sources.sha256.json'))
  if TARGET in before:
   capture=(root/row['evidence']).resolve();after=capture/'sources.after.sha256.json'
   post_captured=capture_input_contract(before,read(after)if after.is_file()else None);post_count+=int(post_captured)
   native_meta=read(inside(capture,'result.json'if kind=='positive'else'case.json'))
   if kind=='positive':
    require(native_meta['status']=='PASS'and native_meta['accepted_native_runner']and native_meta.get('producer_process_exit')==0,'selected positive producer did not exit normally')
    raw=audit_file(capture/'sim.log',True);require(raw['accepted'],'selected positive raw checks failed')
    graph_meta=native_meta;negative=None
   else:
    exits=[native_meta[k]for k in('process_exit','return_code')if k in native_meta]
    require(native_meta['detected']and native_meta['normal_completion']and exits and all(code==1 for code in exits),'selected negative producer exit/completion missing')
    text=(capture/'sim.log').read_text(encoding='utf-8',errors='replace')
    errors=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',text)]
    require('$finish called'in text and '[FAIL'in text and re.search(r'PASS\s+'+re.escape(native_meta['top'])+r'\b|\[TB\]\s*'+re.escape(native_meta['top'])+r'\s+done',text),'selected negative lacks normal semantic detection')
    require(not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',text)and '[SKIP]'not in text and errors==native_meta['error_counts']and any(errors),'selected negative raw error contract differs')
    if native_meta.get('required_marker'):require(native_meta['required_marker']in text,'selected negative semantic marker missing')
    raw=dict(sha256=digest((capture/'sim.log').read_bytes()));negative=native_meta;graph_meta=dict(top=native_meta['top'],suite=native_meta['suite'])
   count=sources(root,capture,negative);observed=graph(root,capture,graph_meta,negative)
   require(count>0 and observed['accepted'],'selected current source/actual compiler graph failed')
   selected.append(dict(kind=kind,evidence=row['evidence'],source_bindings=count,compiler_graph=observed,
    raw_sha256=raw['sha256'],actual_post_run_snapshot_present=post_captured,
    current_inputs_and_raw_rechecked=True,post_run_capture_not_inferred=True))
 require(selected,'qualified clock stimulus has no actual native consumers')
 from audit_v3_native_clock_archive_894 import audit as clock_archive_audit
 clock_archive=clock_archive_audit(root,root/'evidence/v3/packed_clock_261023/native_clock_gate_selftest')
 require(clock_archive['accepted'],'actual3/24 plus3/14 clock archive replay failed')
 result.update(original_archive_relative=archive_path.relative_to(root).as_posix(),current_stimulus_path=TARGET,
  selected_native_captures_bound=len(selected),selected_native_current_rechecks=selected,
  actual_prepost_capture_count=post_count,missing_original_after_snapshot_count=len(selected)-post_count,
  missing_after_snapshot_inferred_as_recorded=False,production_clock_comparisons=219,native_clock_archive_replayed=True,
  proof_sha256={p.relative_to(root).as_posix():digest(p.read_bytes())for p in folder.rglob('*')if p.is_file()},
  STA_approved=False,bitstream_approved=False,hardware_verified=False)
 result['proof_sha256']['safevision/tools/audit_v3_clock_stimulus905.py']=digest(inside(root,'safevision/tools/audit_v3_clock_stimulus905.py').read_bytes())
 return result
def read_bytes_json(raw):return json.loads(raw.decode('utf-8-sig'))
