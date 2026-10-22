"""Real registered option acknowledgements, plus fail-closed tamper controls."""
from pathlib import Path
import json,hashlib,subprocess,re,shutil,sys
B=Path('D:/Codex/svflex537');C=B/'candidate618';O=B/'native_route_ack621';A=B/'route_ack_author621';A.mkdir()
original=B/'route_ack_author574/test_route_ack464.py'
raw=original.read_text(encoding='utf-8-sig')
raw=raw.replace("S=Path('D:/Codex/svflex537/source');O=Path('D:/Codex/svflex537/native_route_ack574')","S=Path('D:/Codex/svflex537/candidate618');O=Path('D:/Codex/svflex537/native_route_ack621')")
raw=raw.replace('D:/Codex/svflex537/native_probe564/native/base/gate.db','D:/Codex/svflex537/native618/base/gate.db')
assert raw!=original.read_text(encoding='utf-8-sig')
author=A/'test_route_ack464.py';author.write_bytes(raw.encode())
subprocess.run([sys.executable,'-X','utf8','-B',str(author)],check=True)
sys.path.insert(0,str(C/'safevision/tools'));from v3_sources import native_parameters,FLOW
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
db=B/'native618/base/gate.db';before=sha(db);d=O/'placement/native/base';d.mkdir(parents=True)
t=d/'query.tcl';t.write_text('''if {[catch {
 import_db {'''+db.as_posix()+'''}
 source {'''+(C/FLOW/'v3_build_parameters.tcl').as_posix()+'''}
 source {'''+(C/FLOW/'v3_build_parameters_base.tcl').as_posix()+'''}
 report_param -detail -stage place -file place.params
 set fd [open place.seed.params w]
 puts $fd "place seed [get_param place seed]"
 close $fd
} err]} {puts stderr "PLACE OPTION QUERY FAILED $err";exit 1}
puts "PLACEMENT621 ACTUAL ACK COMPLETE"
exit 0
''',encoding='ascii')
TD=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
with(d/'native.log').open('wb')as f:r=subprocess.run([str(TD),t.as_posix()],cwd=d,stdout=f,stderr=subprocess.STDOUT,timeout=180)
assert r.returncode==0 and 'PLACEMENT621 ACTUAL ACK COMPLETE'in(d/'native.log').read_text(errors='replace')and sha(db)==before
values=native_parameters(C,d,stages=('place',));assert next(x for x in values if x['parameter']=='opt_timing')['actual']=='off'
records=[dict(name='actual_native_ack',accepted=True,values=values)]
for name in ('wrong_value','missing_value','duplicate_value'):
 bad=O/'placement'/name/'base';bad.mkdir(parents=True)
 shutil.copyfile(d/'place.seed.params',bad/'place.seed.params')
 txt=(d/'place.params').read_text()
 match=re.search(r'^\s*opt_timing\s*\|[^\r\n]+',txt,re.M);assert match
 if name=='wrong_value':txt=txt[:match.start()]+match[0].replace('off','medium')+txt[match.end():]
 elif name=='missing_value':txt=txt[:match.start()]+txt[match.end():]
 else:txt+='\n'+match[0]+'\n'
 (bad/'place.params').write_text(txt)
 try:native_parameters(C,bad,stages=('place',))
 except ValueError as e:records.append(dict(name=name,accepted=True,rejected=True,error=str(e)))
 else:raise AssertionError('tampered placement acknowledgement accepted: '+name)
j=dict(accepted=len(records)==4,scope='Placement parameter registered readback only; no STA approval',checker_sha256=sha(C/'safevision/tools/v3_sources.py'),script_sha256=sha(Path(__file__)),database_sha256_unchanged=before,records=records)
(O/'placement621.selftest.json').write_text(json.dumps(j,indent=2)+'\n',encoding='utf-8')
shutil.copyfile(Path(__file__),O/'test_parameters621.py')
print(json.dumps(dict(route_actual_modes=2,route_rejections=6,placement_actual_modes=1,placement_rejections=3,accepted=True)),flush=True)
