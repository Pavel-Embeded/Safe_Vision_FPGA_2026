"""Portable audit of exact-source native functional evidence; no STA claim."""
import argparse,hashlib,json,re,sys
from pathlib import Path
from audit_v3_raw_logs import audit_file
ROOT=Path(__file__).resolve().parents[2]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def within(root,name):
 p=(root/name).resolve()
 if not p.is_relative_to(root.resolve()):raise ValueError('evidence/source path escaped root')
 return p

def sources(root,folder,negative=None):
 before=read(folder/'sources.sha256.json');assert before
 after=folder/'sources.after.sha256.json'
 if after.exists():assert read(after)==before,'source changed during test'
 changes=0
 for name,digest in before.items():
  assert re.fullmatch('[0-9a-f]{64}',digest)
  p=within(folder,name.split(':',1)[1]) if name.startswith('generated:') else within(root,name)
  if negative and digest==negative['mutated_sha256']:
   assert sha(p)==negative['original_sha256'],'negative baseline changed'
   assert sha(within(folder,negative['mutant_file']))==digest,'missing exact mutant bytes'
   changes+=1
  else:assert p.is_file() and sha(p)==digest,'current source/input differs: '+name
 if negative:assert changes==1,'negative source binding ambiguous'
 return len(before)

def audit(root,manifest):
 j=read(manifest);assert j['schema']==1 and j['complete']
 prior=read(root/'evidence/v3/current_100_20261016/selected_acceptance.json')
 required=set(prior['unique_tops'])|{'tb_v3_command_catalog','tb_v3_uart_link_catalog'}
 core=(root/'safevision/rtl/video/v3_video_display_core.v').read_text()
 if 'v3_scaler_bilinear_thirds s' in core:required.add('tb_v3_thirds_scaler')
 seen=set();rows=[]
 for row in j['positive_tests']:
  assert row['top'] not in seen;seen.add(row['top'])
  folder=within(root,row['evidence']);metadata=read(folder/'result.json')
  assert metadata['top']==row['top'] and metadata['accepted_native_runner'] and not metadata['source_overrides']
  assert sha(folder/'result.json')==row['result_sha256']
  count=sources(root,folder);raw=audit_file(folder/'sim.log',not row['legacy'])
  assert raw['accepted'],raw
  rows.append({'top':row['top'],'source_bindings_checked':count,'raw_log_sha256':raw['sha256']})
 assert seen==required,('required tests missing/extra',sorted(required-seen),sorted(seen-required))
 mutants=[]
 for row in j['negative_controls']:
  folder=within(root,row['evidence']);case=read(folder/'case.json')
  assert case['detected'] and case['normal_completion'];sources(root,folder,case)
  text=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
  assert '$finish called' in text and '[FAIL' in text
  assert re.search(r'PASS\s+'+re.escape(case['top'])+r'\b|\[TB\]\s*'+re.escape(case['top'])+r'\s+done',text)
  assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',text) and '[SKIP]' not in text
  values=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',text)]
  assert values==case['error_counts'] and any(values)
  if case.get('required_marker'):assert case['required_marker'] in text
  assert case['mutation'] not in mutants;mutants.append(case['mutation'])
 assert len(mutants)>=13
 return {'accepted':True,'positive_unique_native_tests':len(required),'strict_normal_ending_mutants':len(mutants),'tests':rows,'source_bytes_and_inputs_verified':True,'routed_sta_passed':False,'bitstreams_verified':False,'hardware_verified':False,'release_ready':False}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--manifest',type=Path,default=Path('evidence/v3/resource_102_20261016/acceptance.json'));ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=audit(a.repo.resolve(),within(a.repo,a.manifest));code=0
 except Exception as ex:r={'accepted':False,'error':str(ex),'release_ready':False};code=1
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2),encoding='utf-8')
 print('RESOURCE CHECKPOINT '+('PASS' if r['accepted'] else 'FAIL'));return code
if __name__=='__main__':sys.exit(main())
