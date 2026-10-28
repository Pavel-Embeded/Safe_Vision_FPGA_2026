"""Exercise the reviewed six-RAM source profile and native location readback."""
from pathlib import Path
import argparse,hashlib,json,shutil,sys,tempfile

ROOT=Path(__file__).resolve().parents[2]

def check(root):
 from v3_sources import FLOW,BASE_MEDIA_BRAM_LOCATIONS,physical_constraint_files,required_media_bram_locations
 from check_v3_board import media_bram_locations
 assets=root/'safevision/verification/assets/bram_layout261028'
 provenance=json.loads((assets/'provenance.json').read_text('utf-8-sig'))
 if provenance['schema']!=1 or len(provenance['records'])!=2:raise ValueError('unexpected native fixture inventory')
 for record in provenance['records']:
  p=(root/record['path']).resolve()
  if not p.is_relative_to(assets.resolve())or hashlib.sha256(p.read_bytes()).hexdigest()!=record['sha256']:raise ValueError('native fixture identity differs')
 expected=dict(BASE_MEDIA_BRAM_LOCATIONS)
 if len(expected)!=6:raise ValueError('expected exactly six media RAM sites')
 old=(assets/'route25.adc').read_text('utf-8-sig');current=(assets/'place45.adc').read_text('utf-8-sig');checks=[]
 def passed(name,condition):
  if not condition:raise ValueError('layout detector failed: '+name)
  checks.append(name)
 good=media_bram_locations(old,expected)
 passed('actual prior native locations',good['accepted']and good['reported_brams']==46)
 passed('different current locations rejected',not media_bram_locations(current,expected)['accepted'])
 first=next(iter(expected));line=f'set_inst_assignment {{{first}}} {{LOCATION = {expected[first]};}}'
 passed('wrong native site rejected',not media_bram_locations(old.replace(line,line.replace(expected[first],'X24Y63Z0')),expected)['accepted'])
 passed('missing native cell rejected',not media_bram_locations(old.replace(line+'\n',''),expected)['accepted'])
 passed('duplicate native cell rejected',not media_bram_locations(old+line+'\n',expected)['accepted'])
 passed('malformed native row rejected',not media_bram_locations(old+'unrecognized report text\n',expected)['accepted'])
 with tempfile.TemporaryDirectory(prefix='sv-media-layout-')as folder:
  scratch=Path(folder);dest=scratch/FLOW;dest.mkdir(parents=True)
  for name in ('v3_physical.adc','v3_physical_base.adc','v3_physical_hd.adc'):
   source=root/FLOW/name
   if source.is_file():shutil.copyfile(source,dest/name)
  p=dest/'v3_physical_base.adc';valid=p.read_text('utf-8-sig')
  passed('exact BASE six-cell profile accepted',required_media_bram_locations(scratch,'base')==expected)
  passed('HD retains its own existing profile',required_media_bram_locations(scratch,'hd')=={})
  cases=[('edited source site',valid.replace('X8Y18Z0','X24Y63Z0')),('partial source group',valid.replace(line+'\n','')),('duplicate source group',valid+line+'\n'),('timing command in physical file',valid+'set_false_path -from [all_registers]\n')]
  for name,bad in cases:
   p.write_text(bad,encoding='utf-8',newline='\n')
   try:physical_constraint_files(scratch,'base')
   except ValueError as error:passed(name+' rejected','unreviewed internal physical constraint'in str(error))
   else:raise ValueError('invalid physical profile accepted: '+name)
  native_lines={f'set_inst_assignment {{{n}}} {{LOCATION = {loc};}}'for n,loc in expected.items()}
  p.write_text('\n'.join(s for s in valid.splitlines()if s not in native_lines)+'\n',encoding='utf-8',newline='\n')
  passed('prior source profile remains valid',required_media_bram_locations(scratch,'base')=={})
 return dict(accepted=True,scope='Source and native-location detector tests; no current routing, STA or board approval',checks=checks,check_count=len(checks))

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--repo',type=Path,default=ROOT);parser.add_argument('--output',type=Path);args=parser.parse_args()
 try:result=check(args.repo.resolve());code=0
 except Exception as error:result=dict(accepted=False,error=type(error).__name__+': '+str(error));code=1
 if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
 print('MEDIA RAM LAYOUT '+('PASS '+str(result['check_count'])+' checks'if result['accepted']else'FAILED '+result['error']))
 return code

if __name__=='__main__':raise SystemExit(main())
