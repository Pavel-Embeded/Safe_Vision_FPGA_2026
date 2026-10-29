
from pathlib import Path
import argparse,hashlib,json,subprocess
from check_auto_ram_placement import check_source,TIMING_AND_PIN_SHA,ADC
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
source=a.source.resolve();out=a.output.resolve()
assert not out.exists()and str(out).isascii()and not out.is_relative_to(source)
out.mkdir(parents=True);fixture=out/'fixture';fixture.mkdir()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
positive=check_source(source);assert positive['accepted']
gold={n:(source/n).read_bytes()for n in [ADC,*TIMING_AND_PIN_SHA]}
gitdir=subprocess.check_output(['git','-C',str(source),'rev-parse','--absolute-git-dir'],text=True).strip()
marker=fixture/'.git';marker_bytes=('gitdir: '+Path(gitdir).as_posix()+'\n').encode('utf-8');marker.write_bytes(marker_bytes)
def restore():
 for n,b in gold.items():
  p=fixture/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
restore();assert check_source(fixture)['accepted']
board=next(n for n in gold if n.endswith('/v3_board.adc'))
sdc=next(n for n in gold if n.endswith('/v3_board.sdc'))
pll=next(n for n in gold if'pll'in Path(n).name.lower()and n.endswith('.v'))
budget=next(n for n in gold if n.endswith('/io_budget.json'))
assert b'R7'in gold[board]and b'x19y31z1'in gold[ADC]
cases=[('wrong_oe_location',ADC,gold[ADC].replace(b'x19y31z1',b'x18y31z1')),
 ('missing_oe',ADC,b''),('added_fixed_ram',ADC,gold[ADC]+b'\nset_inst_assignment {row_guard/ramread0_syn_6} {LOCATION = X8Y9Z0;}\n'),
 ('masked_timing_path',sdc,gold[sdc]+b'\nset_false_path -from [all_clocks] -to [all_clocks]\n'),
 ('moved_board_clock_pin',board,gold[board].replace(b'R7',b'R8',1)),
 ('changed_clock_source_bytes',pll,gold[pll]+b'\n// modified isolated clock source\n'),
 ('changed_io_budget_bytes',budget,gold[budget]+b'\n')]
rows=[]
for name,path,b in cases:
 restore();(fixture/path).write_bytes(b);saved=out/(name+'.bin');saved.write_bytes(b)
 try:check_source(fixture)
 except(ValueError,KeyError,OSError)as exc:rows.append(dict(name=name,rejected=True,target=path,original_sha256=hashlib.sha256(gold[path]).hexdigest(),mutant_sha256=sha(saved),reason=str(exc)))
 else:raise AssertionError('unsafe placement fixture accepted: '+name)
restore();assert check_source(fixture)['accepted']and check_source(source)==positive
assert marker.read_bytes()==marker_bytes and marker.resolve().parent==fixture;marker.unlink()
r=dict(accepted=True,scope='Exact source identity and isolated refusal controls; all routed setup/hold/recovery/removal remain independently mandatory',positive=positive,controls=rows,original_project_unchanged=True)
(out/'verification.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps(dict(accepted=True,rejected_controls=len(rows),fixed_timing_pin_files=len(TIMING_AND_PIN_SHA))))
