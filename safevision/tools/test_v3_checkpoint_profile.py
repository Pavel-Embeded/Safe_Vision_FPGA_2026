"""Exercise actual recorded compilation, then reject seven independent corruptions."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,sys
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'safevision/tools'))
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--native',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
from v3_checkpoint_flow import validate
from v3_source_profiles import native_acknowledgement
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text('utf-8-sig'))
assert validate(root)['accepted']
actual_root=args.source.resolve();original=args.native.resolve()
positive=native_acknowledgement(actual_root,original,'base');assert positive['accepted']
out=args.output.resolve();assert not out.exists()and str(out).isascii()and not out.is_relative_to(root.resolve())and not out.is_relative_to(original);out.mkdir(parents=True)
files=['checkpoint.synthesis.json','build.manifest.json','synthesis.console.log','implementation.console.log','gate.db']
for n in files:shutil.copyfile(original/n,out/n)
raw={n:(out/n).read_bytes()for n in files if n!='gate.db'}
def reset():
 for n,data in raw.items():(out/n).write_bytes(data)
 if sha(out/'gate.db')!=sha(original/'gate.db'):shutil.copyfile(original/'gate.db',out/'gate.db')
def rebind_synth():
 p=out/'checkpoint.synthesis.json';d=read(p);d['synthesis_console_sha256']=sha(out/'synthesis.console.log');p.write_text(json.dumps(d),encoding='utf-8')
def corrupt(name):
 if name in('wrong_order','missing_read_hdl','duplicate_read_hdl'):
  p=out/'synthesis.console.log';s=p.read_text('utf-8',errors='replace');lines=s.splitlines();matches=[i for i,l in enumerate(lines)if l.startswith('RUN-1002 : start command "read_hdl -file ')]
  assert len(matches)==1;i=matches[0]
  if name=='missing_read_hdl':lines.pop(i)
  elif name=='duplicate_read_hdl':lines.insert(i,lines[i])
  else:
   prefix='RUN-1002 : start command "read_hdl -file ';command=lines[i][len(prefix):];inputs,tail=command.split(' -include_dir ',1);items=inputs.split();assert len(items)>2;items[0],items[1]=items[1],items[0];lines[i]=prefix+' '.join(items)+' -include_dir '+tail
  p.write_text('\n'.join(lines)+'\n',encoding='utf-8');rebind_synth()
 elif name=='unlinked_synth':
  p=out/'synthesis.console.log';p.write_bytes(p.read_bytes()+b'\nUNLINKED\n')
 elif name=='wrong_import':
  p=out/'implementation.console.log';s=p.read_text('utf-8',errors='replace');matches=re.findall(r'finish command \"(import_db [^\n]*gate\.db)\"',s);assert len(matches)==1;s=s.replace(matches[0],matches[0].replace('gate.db','other.db'));p.write_text(s,encoding='utf-8')
  p=out/'checkpoint.synthesis.json';d=read(p);d['implementation_console_sha256']=sha(out/'implementation.console.log');p.write_text(json.dumps(d),encoding='utf-8')
 elif name=='changed_gate':(out/'gate.db').write_bytes(b'changed gate fixture')
 elif name=='wrong_commit':
  p=out/'checkpoint.synthesis.json';d=read(p);d['source_commit']='0'*40;p.write_text(json.dumps(d),encoding='utf-8')
 else:raise ValueError(name)
rows=[]
for name in('wrong_order','missing_read_hdl','duplicate_read_hdl','unlinked_synth','wrong_import','changed_gate','wrong_commit'):
 reset();corrupt(name)
 try:native_acknowledgement(actual_root,out,'base')
 except(ValueError,KeyError,OSError)as exc:rows.append(dict(name=name,rejected=True,reason=str(exc)))
 else:raise AssertionError('corruption accepted: '+name)
reset();assert native_acknowledgement(actual_root,out,'base')['accepted'];assert all(sha(out/n)==sha(original/n)for n in files)
# Only the redundant generated database is removed after every fixture check;
# all small control inputs/results and untouched original CAD evidence remain.
assert(out/'gate.db').resolve().parent==out and not(out/'gate.db').is_symlink();(out/'gate.db').unlink()
r=dict(accepted=True,scope='Actual native ordered compilation and checksum-linked synthesis/implementation handoff; timing approval is separate',positive=positive,controls=rows,source_validator=validate(root),source_profiles_sha256=sha(root/'safevision/tools/v3_source_profiles.py'),checkpoint_helper_sha256=sha(root/'safevision/tools/v3_checkpoint_flow.py'),original_native_untouched=True)
(out/'verification.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print(json.dumps(dict(accepted=True,ordered_hdl_count=positive['ordered_hdl_count'],rejected_controls=len(rows))))
