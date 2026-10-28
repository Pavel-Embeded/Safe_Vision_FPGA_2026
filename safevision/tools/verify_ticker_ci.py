"""Verify the current ticker delivery and preserve the original BASE replay."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,os,re,subprocess,sys
from ticker_evidence_archive import unpack
from audit_ticker261028 import audit
from audit_ticker_uart261028 import audit as audit_uart
from replay_ticker_native261028 import replay
from ticker_host_profile261028 import replay as replay_supplementary
from run_v3_board import source_commit_binding
from v3_sources import snapshot

ROOT=Path(__file__).resolve().parents[2]
BASELINE='09faac2e8fa718c9f92ef4a5013b68003ec8afe6'
RELEASE=Path('artifacts/releases/BASE_26102801')
def require(ok,message):
 if not ok:raise ValueError(message)
def read(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def safe(root,name):
 p=PurePosixPath(name);require(not p.is_absolute()and'..'not in p.parts and':'not in name and'\\'not in name,'unsafe delivery path')
 target=root.joinpath(*p.parts);require(target.resolve().is_relative_to(root.resolve()),'delivery path escaped root');return target
def run(argv,cwd,log):
 with log.open('w',encoding='utf-8')as f:code=subprocess.run(argv,cwd=cwd,stdout=f,stderr=subprocess.STDOUT).returncode
 require(code==0,'verification command failed: '+str(log))
def baseline(root,out):
 clone=out/'baseline-source'
 subprocess.run(['git','clone','--shared','--no-checkout',str(root),str(clone)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['git','-C',str(clone),'config','core.longpaths','true'],check=True)
 subprocess.run(['git','-C',str(clone),'sparse-checkout','set','--no-cone','/*','!/artifacts/*','/artifacts/releases/','!/artifacts/releases/*','/artifacts/releases/BASE_26102301_6a957b0/'],check=True)
 subprocess.run(['git','-C',str(clone),'checkout','--detach',BASELINE],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['git','-C',str(clone),'read-tree','--reset','-u','HEAD'],check=True)
 for tool in ('test_base_delivery.py','test_current_base_ci.py','test_repository_records.py'):
  run([sys.executable,'-B',str(clone/'safevision/tools'/tool)],clone,out/(tool+'.log'))
 run([sys.executable,'-B',str(clone/'safevision/tools/audit_repository_records.py'),'--output',str(out/'baseline-records.json')],clone,out/'baseline-records.log')
 run([sys.executable,'-B',str(clone/'safevision/tools/verify_current_base_ci.py'),'--run-dir',str(out/'baseline-replay')],clone,out/'baseline-replay.log')
 result=read(out/'baseline-replay/verification.json');require(result['accepted'],'frozen baseline rejected');return result
def offline(root,release,out):
 index=read(release/'release.index.json')
 require(index['accepted']and index['bitstreams_complete']and index['expected_firmware_id']=='26102801','current release is not approved')
 require(sha(safe(release,index['bitstream']))==index['bit_sha256']and safe(release,index['bitstream']).stat().st_size==index['bit_bytes'],'bitstream identity mismatch')
 require(snapshot(root)==index['source_sha256'],'current physical bytes differ from approved build')
 for name,digest in index['approval_inputs_sha256'].items():require(sha(safe(root,name))==digest,'approval input changed: '+name)
 binding=source_commit_binding(root,root,index['approval_source_commit'],index['approval_inputs_sha256']);require(binding['verified'],'approval commit no longer binds delivery inputs')
 require(read(release/'functional.audit.json')['accepted']and read(release/'base.gate.json')['gate_accepted'],'saved approval failed')
 require(sha(release/'functional.audit.json')==index['functional_audit_sha256']and sha(release/'base.gate.json')==index['native_gate_sha256'],'saved approval checksums differ')
 archive=safe(root,index['evidence_archive']);require(sha(archive)==index['evidence_archive_sha256'],'evidence archive changed')
 unpack(archive,out/'proof');proof=out/'proof'
 functional=audit(root,proof/'regression',proof/'ticker',proof/'board',proof/'controls')
 require(index.get('production_profile')==functional['production_profile']and read(release/'functional.audit.json')['production_profile']==functional['production_profile'],'release production profile differs from current local32 proof')
 native=replay(root,proof/'native')
 require(native['gate']['sta']['negative_path_count']==0,'native replay contains negative paths')
 return dict(accepted=True,index=index,functional=functional,native=native,bit_sha256=index['bit_sha256'],fresh_TD_build_performed=False,hardware_test_performed=False)

def verify(root,out):
 release=root/RELEASE;delivery=read(release/'delivery.manifest.json')
 require(delivery['schema']==1 and delivery['profile']=='ticker261028','unknown delivery profile')
 for name,digest in delivery['files_sha256'].items():require(sha(safe(release,name))==digest,'delivery checksum mismatch: '+name)
 files={p.relative_to(release).as_posix()for p in release.rglob('*')if p.is_file()}
 require(files==set(delivery['files_sha256'])|{'delivery.manifest.json'},'unlisted or missing release file')
 require(delivery['files_sha256']['release.index.json']==sha(release/'release.index.json'),'release index not bound')
 result=offline(root,release,out);index=result['index'];functional=result['functional'];native=result['native']
 programmed=read(release/'board/programming/programming.json')
 require(programmed['program_sram_command_succeeded']and programmed['process_exit']==0 and programmed['bit_sha256']==index['bit_sha256'],'programming receipt does not identify the approved bitstream')
 require(programmed['expected_firmware_id']=='26102801'and programmed['approval_source_commit']==index['approval_source_commit']and programmed['flash_written']is False,'programming approval or target differs')
 console=release/'board/programming/download.console.log';require(sha(console)==programmed['console_sha256'],'programming log changed')
 raw=console.read_bytes();text=raw.decode('utf-16')if raw.startswith((b'\xff\xfe',b'\xfe\xff'))else raw.decode('utf-8-sig',errors='replace')
 require(re.search(r'Chip\s*validation success: EG4S20BG256',text)and'BW_TICKER_SRAM_COMPLETED'in text and'finish command "download -bit'in text,'normal hardware download markers missing')
 require('BW_TICKER_SRAM_FAILED'not in text and'Unknown cable'not in text and'USB device open error'not in text,'programming log reports cable or download failure')
 require(not re.search(r'(?im)\bERROR\b',text),'programming log contains an error')
 uart=audit_uart(release/'board/regression')
 require(uart['period_pixels']==index['production_profile']['period_pixels'],'UART cadence profile differs from the approved bitstream')
 supplementary=replay_supplementary(root,release/'board',out/'supplementary')
 physical=read(release/'board/physical_acceptance.json')
 require(physical['firmware_id']=='26102801'and physical['bit_sha256']==index['bit_sha256'],'physical observation has wrong image identity')
 require(all(physical[k]is True for k in('chinese_legible','scroll_smooth','uptime_visible','spectrum_visible','pictures_normal','audio_normal')),'physical visual/audio acceptance missing')
 for name,digest in delivery['files_sha256'].items():require(sha(safe(release,name))==digest,'delivery input changed during replay: '+name)
 return dict(accepted=True,current_source_verified=True,baseline_commit=BASELINE,expected_firmware_id='26102801',physical_inputs=len(index['source_sha256']),functional=functional,native=native,uart=uart,supplementary=supplementary,physical_acceptance_sha256=sha(release/'board/physical_acceptance.json'),bit_sha256=index['bit_sha256'],fresh_TD_build_performed=False,hardware_test_performed=False,scope='Checksum and independent evidence replay; physical observations remain attributed to the recorded board session')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--run-dir',type=Path,required=True);a=ap.parse_args();out=a.run_dir.resolve();require(not out.exists()and not out.is_relative_to(a.repo.resolve()),'fresh isolated audit directory required');out.mkdir(parents=True)
 try:
  for tool in ('test_ticker_archive261028.py','test_ticker_uart261028.py'):
   run([sys.executable,'-B',str(a.repo.resolve()/'safevision/tools'/tool)],a.repo.resolve(),out/(tool+'.log'))
  old=baseline(a.repo.resolve(),out);r=verify(a.repo.resolve(),out);r['baseline_replay_sha256']=sha(out/'baseline-replay/verification.json')
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e),fresh_TD_build_performed=False,hardware_test_performed=False)
 (out/'verification.json').write_text(json.dumps(r,indent=2)+'\n','utf-8');print('BASE TICKER DELIVERY REPLAY '+('PASS'if r['accepted']else'FAILED: '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
