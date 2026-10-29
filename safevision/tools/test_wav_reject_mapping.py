
from pathlib import Path
import argparse,hashlib,json,subprocess
from check_wav_reject_mapping import check_parser,SOURCE,NAMES

p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
source=a.source.resolve();out=a.output.resolve()
assert not out.exists()and str(out).isascii()and not out.is_relative_to(source)
out.mkdir(parents=True);fixture=out/'fixture';fixture.mkdir()
gold=(source/SOURCE).read_bytes();positive=check_parser(source);assert positive['accepted']
gitdir=subprocess.check_output(['git','-C',str(source),'rev-parse','--absolute-git-dir'],text=True).strip()
marker=fixture/'.git';marker_bytes=('gitdir: '+Path(gitdir).as_posix()+'\n').encode();marker.write_bytes(marker_bytes)
target=fixture/SOURCE;target.parent.mkdir(parents=True)
target.write_bytes(gold);assert check_parser(fixture)==positive
cases=[]
for name in NAMES:
 before=('(* keep="true" *) wire '+name+'=').encode()
 assert gold.count(before)==1
 cases.append(('missing_'+name,gold.replace(before,('wire '+name+'=').encode())))
cases.extend([('lost_tail_error',gold.replace(b'wire reject_tail=(riff_left==0)||',b"wire reject_tail=1'b0||")),('pcm_not_suppressed',gold.replace(b'if(reject_now)begin wav_error<=1;pcm_valid<=0;',b'if(reject_now)begin wav_error<=1;pcm_valid<=1;'))])
rows=[]
for name,raw in cases:
 assert raw!=gold
 target.write_bytes(raw);mutant=out/(name+'.v');mutant.write_bytes(raw)
 try:check_parser(fixture)
 except(ValueError,KeyError,OSError)as exc:rows.append(dict(name=name,rejected=True,mutant_sha256=hashlib.sha256(raw).hexdigest(),reason=str(exc)))
 else:raise AssertionError('unreviewed parser accepted: '+name)
target.write_bytes(gold);assert check_parser(fixture)==positive and(source/SOURCE).read_bytes()==gold
assert marker.read_bytes()==marker_bytes and marker.resolve().parent==fixture;marker.unlink()
result=dict(accepted=True,scope='Source-identity refusal controls. HDL semantic detection remains the unchanged frozen regression inventory.',positive=positive,controls=rows,original_project_unchanged=True)
(out/'verification.json').write_text(json.dumps(result,indent=2)+'\n','utf-8')
print(json.dumps(dict(accepted=True,refused_controls=len(rows))))
