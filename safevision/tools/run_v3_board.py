"""Native TD V3 builder. Both requested modes must pass before any bitgen."""
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
from datetime import datetime,timezone
from v3_sources import ROOT,FLOW,snapshot,gui_project,check_gui
from check_v3_board import check,resource_gate,read_report
from check_v3_rom_netlist import check_roms
from v3_final_sta import reassess
def save(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def source_commit_binding(root,source_repo,ref,paths):
 """Tie the actual build bytes to committed Git blobs, including text filters."""
 def git(*args,**kwargs):return subprocess.run(['git','-C',str(source_repo),*args],capture_output=True,**kwargs)
 revision=git('rev-parse',ref+'^{commit}')
 if revision.returncode:return {'verified':False,'commit':None,'reason':'source Git commit is unavailable'}
 commit=revision.stdout.decode('ascii').strip();tree=git('ls-tree','-rz',commit)
 if tree.returncode:return {'verified':False,'commit':commit,'reason':'source Git tree is unavailable'}
 blobs={}
 for row in tree.stdout.split(b'\0'):
  if not row:continue
  meta,path=row.split(b'\t',1);parts=meta.split()
  if parts[1]==b'blob':blobs[path.decode('utf-8')]=parts[2].decode('ascii')
 errors=[]
 for name in paths:
  if name not in blobs:errors.append('uncommitted build dependency: '+name);continue
  hashed=git('hash-object','--stdin','--path='+name,input=(root/name).read_bytes())
  if hashed.returncode or hashed.stdout.decode('ascii').strip()!=blobs[name]:errors.append('build bytes differ from source commit: '+name)
 return {'verified':not errors,'commit':commit,'source_repository':str(source_repo),'dependencies_compared':len(paths),'errors':errors}
def invoke(exe,tcl,log,env):
 with log.open('w',encoding='utf-8') as f:p=subprocess.run([str(exe),tcl.as_posix()],env=env,stdout=f,stderr=subprocess.STDOUT,timeout=3600)
 text=log.read_text(encoding='utf-8',errors='replace')
 if p.returncode or re.search(r'V3 TD FAILED|\bERROR:|HDL-\d+ ERROR|multiple drivers?|HDL-5105 CRITICAL-WARNING',text,re.I):raise RuntimeError('TD failed: '+str(log))
 return p.returncode,text
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--run-dir',type=Path,required=True)
 ap.add_argument('--td-root',type=Path,default=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116'))
 ap.add_argument('--mode',action='append');ap.add_argument('--bitgen',action='store_true');ap.add_argument('--synth-only',action='store_true')
 ap.add_argument('--source-repo',type=Path,help='Git source for a clean isolated build copy')
 ap.add_argument('--source-ref',default='HEAD');a=ap.parse_args()
 root=a.repo.resolve();out=a.run_dir.resolve();modes=a.mode or ['base','hd']
 if len(modes)!=len(set(modes)) or set(modes)-{'base','hd'}:raise ValueError('invalid or duplicate modes')
 if a.bitgen and a.synth_only:raise ValueError('synthesis-only cannot generate a bitstream')
 if a.bitgen and set(modes)!={'base','hd'}:raise ValueError('release bitgen requires both BASE and HD in this invocation')
 if not str(out).isascii():raise ValueError('TD run directory must be ASCII')
 exe=a.td_root/'bin/td_commands_prompt.exe'
 if not exe.is_file():raise FileNotFoundError(exe)
 out.mkdir(parents=True,exist_ok=True)
 for mode in modes:
  folder=out/mode
  if folder.exists() and any(folder.iterdir()):raise ValueError('use a new empty mode directory: '+str(folder))
 for mode in ('base','hd'):gui_project(root,mode)
 gui=[check_gui(root,m) for m in ('base','hd')];before=snapshot(root)
 env=os.environ.copy();env['SAFEVISION_REPO']=str(root);env['SAFEVISION_V3_OUT']=str(out);env['SAFEVISION_V3_SYNTH_ONLY']='1' if a.synth_only else '0'
 binding=source_commit_binding(root,(a.source_repo or root).resolve(),a.source_ref,before)
 if a.bitgen and not binding['verified']:raise RuntimeError('release source is not an exact committed tree: '+json.dumps(binding,ensure_ascii=False))
 records=[]
 for mode in modes:
  folder=out/mode;folder.mkdir(exist_ok=True)
  record={'mode':mode,'status':'NOT_RUN','sources':before,'gui_cli':gui,'source_commit':binding['commit'],'source_commit_binding':binding,
   'td_executable':str(exe),'td_executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),
   'source_identity':'actual build SHA-256 bytes plus explicit Git blob comparison; inspect source_commit_binding.verified',
   'source_unchanged':False,'bit_generated':False,'hardware_verified':False,'created_at_utc':datetime.now(timezone.utc).isoformat()}
  manifest=folder/'build.manifest.json';save(manifest,record)
  try:
   route_exit,text=invoke(exe,root/FLOW/(mode+'.tcl'),out/(mode+'.console.log'),env)
   marker='V3 TD SYNTHESIZED' if a.synth_only else 'V3 TD ROUTED'
   if marker not in text:raise RuntimeError('missing normal TD completion marker')
   version=re.search(r'Tang Dynasty,\s*(V[0-9.]+)',text)
   if not version:raise RuntimeError('missing TD version banner')
   record['td_version']=version[1]
   if snapshot(root)!=before:raise RuntimeError('sources changed during TD run; rerun a frozen snapshot')
   record['source_unchanged']=True
   if a.synth_only:
    record['mapped_roms']=check_roms(read_report(folder/'gate.netlist.v'),root)
    record['resource_gate']=resource_gate(read_report(folder/'gate.area'))
    record['status']='SYNTHESIZED_ONLY' if record['resource_gate']['accepted'] else 'RESOURCE_REJECTED'
   else:
    record['final_sta_integrity']=reassess(exe,folder,[root/FLOW/'v3_board.sdc',root/FLOW/'v3_cdc.sdc'],root/FLOW/'v3_cdc_audit.tcl',env,route_process_exit_code=route_exit)
    if snapshot(root)!=before:raise RuntimeError('sources changed during fresh-process final STA')
    verdict=check(folder,root);save(folder/'timing.gate.json',verdict)
    record['gate']=verdict;record['status']=verdict['status']
  except Exception as ex:record['status']='FAIL';record['error']=str(ex)
  records.append(record);save(manifest,record);print(mode+': '+record['status'],flush=True)
 required='SYNTHESIZED_ONLY' if a.synth_only else 'PASS'
 accepted=len(records)==len(modes) and all(r['status']==required for r in records)
 if accepted and a.bitgen:
  for record in records:
   mode=record['mode'];folder=out/mode
   if snapshot(root)!=before:raise RuntimeError('sources changed before bitgen')
   for report in record['gate']['reports']:
    if hashlib.sha256(Path(report['path']).read_bytes()).hexdigest()!=report['sha256']:raise RuntimeError('approved routed report/database changed')
   bit=folder/'safevision_v3_top.bit';pending=folder/'safevision_v3_top.pending.bit';tcl=folder/'approved_bitgen.tcl'
   tcl.write_text('if {[catch {\n import_db {'+(folder/'route.db').as_posix()+'}\n bitgen -bit {'+pending.as_posix()+'}\n export_bitgen_param -file {'+(folder/'bitgen.params').as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "V3 BITGEN COMPLETE"\nexit 0\n',encoding='ascii')
   bit_exit,text=invoke(exe,tcl,folder/'bitgen.console.log',env)
   if 'V3 BITGEN COMPLETE' not in text or not pending.is_file() or not pending.stat().st_size:raise RuntimeError('bitgen did not finish')
   if snapshot(root)!=before:raise RuntimeError('sources changed during bitgen')
   for report in record['gate']['reports']:
    if hashlib.sha256(Path(report['path']).read_bytes()).hexdigest()!=report['sha256']:raise RuntimeError('routed evidence changed during bitgen')
   pending.replace(bit);record['bit_generated']=True;record['bitstream']={'path':str(bit),'bytes':bit.stat().st_size,'sha256':hashlib.sha256(bit.read_bytes()).hexdigest()}
   save(folder/'build.manifest.json',record)
 save(out/'build.summary.json',{'accepted':accepted,'synthesis_only':a.synth_only,'modes':[{k:v for k,v in r.items() if k not in ('sources','gate','gui_cli')} for r in records]})
 return 0 if accepted else 1
if __name__=='__main__':sys.exit(main())
