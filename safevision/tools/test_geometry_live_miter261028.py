"""Verify the frozen parent and exercise a normally finishing PUBLIC miter control."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--repo',type=Path,required=True);parser.add_argument('--positive',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
 root=args.repo.resolve();positive=args.positive.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
 target='safevision/rtl/media/v3_bmp_normalizer.v';top='tb_v3_geometry_live_miter';model='safevision/verification/models/v3_bmp_normalizer_frozen_live261028.sv';meta='safevision/verification/models/v3_bmp_normalizer_frozen_live261028.freeze.json'
 record=dict(accepted=False,scope='Frozen-parent identity and one normal semantic PUBLIC-port control; not original-matrix, timing or board acceptance')
 try:
  provenance=json.loads((root/meta).read_text('utf-8'))
  parent=subprocess.check_output(['git','-C',str(root),'show',provenance['parent_commit']+':'+target])
  assert hashlib.sha256(parent).hexdigest()==provenance['original_sha256']
  before=provenance['rename_from'].encode();after=provenance['rename_to'].encode();assert parent.count(before)==1
  expected=parent.replace(before,after);assert(root/model).read_bytes()==expected
  assert sha(root/model)==provenance['reference_sha256']
  source_sha=sha(root/target);assert source_sha==provenance['candidate_sha256']
  result=json.loads((positive/'results.json').read_text());assert result['complete']and len(result['results'])==1
  row=result['results'][0];assert row['status']=='PASS'and row['top']==top and row['data_comparisons']>30000000 and row['source_overrides']==[]
  for first,last in [('generation.before.sha256.json','generation.after.sha256.json'),('sources.sha256.json','sources.after.sha256.json')]:
   assert json.loads((positive/top/first).read_text())==json.loads((positive/top/last).read_text())
  files=json.loads((positive/top/'sources.sha256.json').read_text());assert files[target]==source_sha and files[model]==sha(root/model)
  for name,value in files.items():
   if name.startswith('generated:'):assert sha(positive/top/name[10:])==value
   else:assert sha(root/name)==value,name
  raw=(root/target).read_text('utf-8-sig');before="EPUSH:begin pixel<=row_black||col_black?16'd0:read_pixel;";after="EPUSH:begin pixel<=(row_black||col_black?16'd0:read_pixel)^16'h0001;";assert raw.count(before)==1
  mutant=out/'public_state_mutant.v';mutant.write_text(raw.replace(before,after),'utf-8',newline='\n')
  argv=[sys.executable,'-B',str(root/'safevision/tools/run_v3_sim_flexible.py'),'--suite','geometry_live_miter261028','--run-dir',str(out/'native'),'--override-source',target+'='+str(mutant)]
  with(out/'console.log').open('w',encoding='utf-8')as log:code=subprocess.run(argv,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=1800).returncode
  sim=out/'native'/top/'sim.log';text=sim.read_text('utf-8',errors='replace');counts=[int(n)for n in re.findall(r'errors\s*=\s*(\d+)',text)]
  assert code==1 and'$finish called'in text and'PASS '+top in text and counts and any(counts)
  assert'[FAIL] all62FLEX public bits agree'in text
  pattern=r'PASS '+top+r' errors=(\d+) comparisons=(\d+) cycles=(\d+) frames=(\d+) invalid_sizes=(\d+) invalid_eofs=(\d+) async_checks=(\d+) stalled_cycles=(\d+)'
  positive_counters=re.search(pattern,(positive/top/'sim.log').read_text());negative_counters=re.search(pattern,text)
  assert positive_counters and negative_counters and positive_counters[1]=='0'
  assert positive_counters.groups()[1:]==negative_counters.groups()[1:],'payload-only mutation changed protocol timing/coverage'
  assert int(negative_counters[1])>=307200 and list(map(int,negative_counters.groups()[3:7]))==[12,16,5,5]
  assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',text)
  assert sha(root/target)==source_sha and(root/model).read_bytes()==expected
  negative_files=json.loads((out/'native'/top/'sources.sha256.json').read_text());assert negative_files[target]==sha(mutant)
  for first,last in [('generation.before.sha256.json','generation.after.sha256.json'),('sources.sha256.json','sources.after.sha256.json')]:assert json.loads((out/'native'/top/first).read_text())==json.loads((out/'native'/top/last).read_text())
  record.update(accepted=True,parent_commit=provenance['parent_commit'],parent_source_sha256=provenance['original_sha256'],reference_sha256=sha(root/model),rename_only=True,current_source_sha256=source_sha,positive_receipt=str(positive/'results.json'),positive_sha256=sha(positive/'results.json'),positive_comparisons=row['data_comparisons'],control=dict(name='geometry_live_pixel_bit_changed',mutated_public_signal='pixel[0]',process_exit=code,normal_completion=True,error_counts=counts,protocol_and_coverage_counters_equal=True,mutant_sha256=sha(mutant),sim_sha256=sha(sim)),tool_sha256=sha(Path(__file__)))
 except Exception as error:record['error']=type(error).__name__+': '+str(error)
 (out/'summary.json').write_text(json.dumps(record,indent=2)+'\n','utf-8');print('LIVE PUBLIC MITER CONTROL '+('PASS'if record['accepted']else'FAIL: '+record['error']));return 0 if record['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
