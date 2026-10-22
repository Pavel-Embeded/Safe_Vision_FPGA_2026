"""Four-feature bitgen with complete evidence, exact commits and strict STA.

The explicit BASE engineering option does not approve HD or a two-mode release.
"""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,os,re,subprocess,sys

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,j):p.write_text(json.dumps(j,indent=2)+'\n',encoding='utf-8')
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--native-run',type=Path,required=True);ap.add_argument('--functional-manifest',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--check-only',action='store_true');ap.add_argument('--engineering-base-only',action='store_true',help='Explicit BASE engineering output; never approves HD');a=ap.parse_args()
 if not __debug__:raise RuntimeError('assertions must remain enabled')
 root=a.repo.resolve();run=a.native_run.resolve();out=a.output.resolve()
 if not str(out).isascii()or out.is_relative_to(root)or root.is_relative_to(out):raise ValueError('isolated ASCII output directory required')
 if out.exists()and any(out.iterdir()):raise ValueError('fresh output directory required')
 out.mkdir(parents=True,exist_ok=True);sys.path.insert(0,str(root/'safevision/tools'))
 from audit_v3_four_features import audit
 from finalize_v3_board_release import native_acceptance,ensure_unchanged
 from run_v3_board import source_commit_binding,invoke
 from v3_sources import snapshot
 modes=('base',)if a.engineering_base_only else('base','hd')
 summary=dict(schema=2,profile='four_features_261020',accepted=False,bitstreams_complete=False,two_mode_release=False,engineering_candidate=a.engineering_base_only,requested_modes=list(modes),hardware_verified=False,flash_written=False,github_upload_performed=False,created_at_utc=datetime.now(timezone.utc).isoformat())
 try:
  functional=audit(root,a.functional_manifest,root)
  if not functional['accepted']:raise ValueError('complete current-source functional approval required')
  hardware=snapshot(root);proof=functional['proof_sha256'];commit=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD']).decode().strip()
  binding=source_commit_binding(root,root,commit,{**hardware,**proof})
  if not binding['verified']:raise ValueError('uncommitted source, proof or checker: '+repr(binding['errors']))
  natives=[native_acceptance(root,run,mode,hardware)for mode in modes]
  if any(n['record']['source_commit']!=functional['source_build_commit']for n in natives):raise ValueError('every requested native build must bind the selected build commit')
  ensure_unchanged(root,hardware,proof,natives)
  top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text()
  ids=re.findall(r'b_diag_next0=.*?32\x27h([0-9A-Fa-f]{8})',top);assert len(ids)==1
  summary.update(accepted=True,approval_source_commit=commit,design_build_commit=functional['source_build_commit'],expected_firmware_id=ids[0].upper(),source_commit_binding=binding,source_sha256=hardware,proof_sha256=proof,functional_acceptance=functional)
  for n in natives:save(out/(n['mode']+'.gate.json'),n['gate'])
  if a.check_only:summary['check_only']=True
  else:
   bits=[]
   for native in natives:
    ensure_unchanged(root,hardware,proof,natives);mode=native['mode'];folder=native['folder'];pending=out/(mode+'.pending.bit');tcl=out/(mode+'.bitgen.tcl')
    tcl.write_text('if {[catch {\n import_db {'+(folder/'route.db').as_posix()+'}\n bitgen -bit {'+pending.as_posix()+'}\n export_bitgen_param -file {'+(out/(mode+'.bitgen.params')).as_posix()+'}\n} err]} {puts stderr "V3 TD FAILED: $err";exit 1}\nputs "V3 BITGEN COMPLETE"\nexit 0\n',encoding='ascii')
    code,text=invoke(native['exe'],tcl,out/(mode+'.bitgen.console.log'),os.environ.copy())
    if code or 'V3 BITGEN COMPLETE'not in text or not pending.is_file()or not pending.stat().st_size:raise RuntimeError(mode+': bitgen did not complete normally')
    ensure_unchanged(root,hardware,proof,natives)
    bits.append(dict(mode=mode,pending=pending,bytes=pending.stat().st_size,sha256=sha(pending),design_build_commit=native['record']['source_commit'],route_database_sha256=sha(folder/'route.db'),td_version=native['record']['td_version'],td_executable_sha256=native['record']['td_executable_sha256'],native_parameters=native['record']['native_parameters'],bitgen_console_sha256=sha(out/(mode+'.bitgen.console.log')),bitgen_script_sha256=sha(tcl),bitgen_parameters_sha256=sha(out/(mode+'.bitgen.params'))))
   ensure_unchanged(root,hardware,proof,natives)
   for row in bits:
    p=out/('SafeVision_'+row['mode'].upper()+'_'+commit[:7]+'.bit');row.pop('pending').replace(p);row['path']=str(p)
   summary.update(bitstreams=bits,bitstreams_complete=True,two_mode_release=set(modes)=={'base','hd'})
  save(out/'release.index.json',summary);print('FOUR FEATURE FINALIZATION PASS: '+str(out),flush=True);return 0
 except Exception as e:
  summary.update(accepted=False,bitstreams_complete=False,error=type(e).__name__+': '+str(e));save(out/'release.index.json',summary);print('FOUR FEATURE FINALIZATION REJECTED: '+summary['error'],flush=True);return 1
if __name__=='__main__':sys.exit(main())
