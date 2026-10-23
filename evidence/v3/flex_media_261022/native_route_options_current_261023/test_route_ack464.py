"""Exercise actual native route-option acknowledgement and reject tampering."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys
S=Path('D:/Codex/svflex537/candidate892');O=Path('D:/Codex/svflex537/native_route_ack_current_261023_01');O.mkdir();F=S/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify'
sys.path.insert(0,str(S/'safevision/tools'));from v3_sources import native_parameters
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
TD=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
records=[]
for mode,db in [('base',Path('D:/Codex/svflex537/native892/base/gate.db')),('hd',Path('D:/Codex/svarea427/pr14/hd/place.db'))]:
 d=O/'native'/mode;d.mkdir(parents=True);before=sha(db)
 script=d/'query.tcl';script.write_text('''if {[catch {
 import_db {'''+db.as_posix()+'''}
 source {'''+(F/'v3_build_parameters.tcl').as_posix()+'''}
 source {'''+(F/('v3_build_parameters_'+mode+'.tcl')).as_posix()+'''}
 report_param -detail -stage route -file route.params
 set fd [open route.hidden.params w]
 puts $fd "route post_route_opt [get_param route post_route_opt]"
 close $fd
} err]} {puts stderr "ROUTE OPTION QUERY FAILED: $err";exit 1}
puts "ROUTE_PARAM_NATIVE_ACK_COMPLETE"
exit 0
''',encoding='ascii')
 with(d/'native.log').open('wb')as f:rc=subprocess.run([str(TD),script.as_posix()],cwd=d,stdout=f,stderr=subprocess.STDOUT,timeout=180).returncode
 assert rc==0 and 'ROUTE_PARAM_NATIVE_ACK_COMPLETE'in(d/'native.log').read_text(errors='replace')and sha(db)==before
 assert not re.search(r'(?im)^\s*ERROR:|ROUTE OPTION QUERY FAILED',(d/'native.log').read_text(errors='replace'))
 values=native_parameters(S,d,stages=('route',));assert len(values)==4
 records.append(dict(mode=mode,name='actual_native_ack',accepted=True,process_exit=rc,source_database_sha256_unchanged=before,values=values))
 for kind in ('wrong_hidden_value','missing_hidden_value','wrong_ordinary_value'):
  bad=O/kind/mode;bad.mkdir(parents=True);shutil.copyfile(d/'route.params',bad/'route.params')
  if kind!='missing_hidden_value':shutil.copyfile(d/'route.hidden.params',bad/'route.hidden.params')
  if kind=='wrong_hidden_value':
   p=bad/'route.hidden.params';p.write_text('route post_route_opt '+('auto' if next(v['actual'] for v in values if v['parameter']=='post_route_opt')!='auto' else 'ultra')+'\n')
  elif kind=='wrong_ordinary_value':
   p=bad/'route.params';text=p.read_text();text,n=re.subn(r'(^\s*timing\s*\|\s*)(\w+)(\s*\|)',lambda m:m[1]+('off' if next(v['actual'] for v in values if v['parameter']=='timing')!='off' else 'on')+m[3],text,flags=re.M);assert n==1;p.write_text(text)
  try:native_parameters(S,bad,stages=('route',))
  except (ValueError,FileNotFoundError)as e:records.append(dict(mode=mode,name=kind,accepted=True,rejected=True,error=type(e).__name__+': '+str(e)))
  else:raise AssertionError('tampered native acknowledgement accepted: '+str(bad))
summary=dict(accepted=len(records)==8 and all(r['accepted']for r in records),scope='native route parameter acknowledgement only',functional_approval=False,routed_STA_approval=False,bitgen_performed=False,github_uploaded=False,records=records,checker_sha256=sha(S/'safevision/tools/v3_sources.py'),test_sha256=sha(Path(__file__)))
(O/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');assert summary['accepted'];print(json.dumps(dict(accepted=True,actual_native_modes=2,required_rejections=6,routed_STA_approval=False)),flush=True)
