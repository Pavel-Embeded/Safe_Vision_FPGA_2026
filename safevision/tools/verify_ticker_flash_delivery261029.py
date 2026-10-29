"""Verify the Flash-install delivery using the user-selected short board profile."""
from pathlib import Path
import argparse,hashlib,json,re,sys
from verify_ticker_ci import ROOT,RELEASE,BASELINE,offline,baseline,read,sha,require,safe,run
from audit_ticker_uart261028 import audit as audit_uart
from ticker_host_profile261028 import replay as supplementary
from verify_ticker_flash261028 import verify as flash_verify

PROFILE='flash_install261029'

def policy_check(policy):
    require(policy['schema']==1 and policy['profile']==PROFILE,'Unknown board acceptance profile')
    require(policy['minimum_continuous_monitor_seconds']==60 and policy['manual_transitions']==100 and policy['recoveries']==10,'Changed short-profile limits')
    require(policy['two_hour_test_required'] is False and policy['two_hour_pass_claimed'] is False,'Incorrect two-hour test claim')
    require(policy['change_authorized_by']=='user' and '不用两个小时的检测了' in policy['user_verbatim'],'Short profile lacks explicit user instruction')
    return policy

def verify(root,out):
    release=root/RELEASE;delivery=read(release/'delivery.manifest.json');policy=policy_check(read(release/'acceptance.policy.json'))
    require(delivery['schema']==1 and delivery['profile']=='ticker261028'and delivery['acceptance_profile']==PROFILE,'Delivery acceptance profile differs')
    for name,digest in delivery['files_sha256'].items():require(sha(safe(release,name))==digest,'Delivery checksum mismatch: '+name)
    files={p.relative_to(release).as_posix()for p in release.rglob('*')if p.is_file()}
    require(files==set(delivery['files_sha256'])|{'delivery.manifest.json'},'Unlisted or missing release file')
    result=offline(root,release,out);index=result['index']
    programmed=read(release/'board/programming/programming.json')
    require(programmed['program_sram_command_succeeded']and programmed['process_exit']==0 and programmed['bit_sha256']==index['bit_sha256'],'Original programming identity differs')
    require(programmed['expected_firmware_id']=='26102801'and programmed['approval_source_commit']==index['approval_source_commit']and programmed['flash_written']is False,'Original SRAM programming receipt changed')
    console=release/'board/programming/download.console.log';require(sha(console)==programmed['console_sha256'],'Original programming log changed')
    raw=console.read_bytes();text=raw.decode('utf-16')if raw.startswith((b'\xff\xfe',b'\xfe\xff'))else raw.decode('utf-8-sig',errors='replace')
    require(re.search(r'Chip\s*validation success: EG4S20BG256',text)and'BW_TICKER_SRAM_COMPLETED'in text and'finish command "download -bit'in text,'Original download completion missing')
    require(not re.search(r'(?im)\bERROR\b|BW_TICKER_SRAM_FAILED|Unknown cable|USB device open error',text),'Original programming failure')
    uart=audit_uart(release/'board/regression',minimum_seconds=policy['minimum_continuous_monitor_seconds'],transitions=policy['manual_transitions'],recoveries=policy['recoveries'])
    require(uart['period_pixels']==index['production_profile']['period_pixels'],'UART cadence profile differs')
    supp=supplementary(root,release/'board',out/'supplementary')
    physical=read(release/'board/physical_acceptance.json')
    require(physical['firmware_id']=='26102801'and physical['bit_sha256']==index['bit_sha256'],'Physical observation image differs')
    require(all(physical[k]is True for k in('chinese_legible','scroll_smooth','uptime_visible','spectrum_visible','pictures_normal','audio_normal')),'Physical feedback incomplete')
    flash=flash_verify(release)
    cold=read(release/'board/cold_boot_user_report.json')
    require(cold['evidence_kind']=='user_report'and cold['cold_power_cycle_passed_user_report']and cold['bit_sha256']==index['bit_sha256'],'Cold-start user observation missing')
    require(cold['user_verbatim']=='已断电重接，各项正常'and cold['machine_verified_power_removal']is False,'Cold-start evidence attribution changed')
    for name,digest in delivery['files_sha256'].items():require(sha(safe(release,name))==digest,'Delivery input changed during replay: '+name)
    return dict(accepted=True,current_source_verified=True,acceptance_profile=PROFILE,two_hour_test_required=False,two_hour_pass_claimed=False,minimum_continuous_monitor_seconds=60,baseline_commit=BASELINE,expected_firmware_id='26102801',physical_inputs=len(index['source_sha256']),functional=result['functional'],native=result['native'],uart=uart,supplementary=supp,flash=flash,physical_acceptance_sha256=sha(release/'board/physical_acceptance.json'),cold_boot_user_report_sha256=sha(release/'board/cold_boot_user_report.json'),bit_sha256=index['bit_sha256'],fresh_TD_build_performed=False,hardware_test_performed=False,scope='Saved evidence replay; short install profile explicitly selected by user, original two-hour verifier retained unchanged')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--repo',type=Path,default=ROOT);parser.add_argument('--run-dir',type=Path,required=True);args=parser.parse_args();root=args.repo.resolve();out=args.run_dir.resolve()
    require(not out.exists()and not out.is_relative_to(root),'Fresh isolated verification directory required');out.mkdir(parents=True)
    try:
        for tool in('test_ticker_archive261028.py','test_ticker_uart261028.py','test_ticker_flash261028.py','test_ticker_flash_policy261029.py'):
            run([sys.executable,'-B',str(root/'safevision/tools'/tool)],root,out/(tool+'.log'))
        old=baseline(root,out);result=verify(root,out);result['baseline_replay_sha256']=sha(out/'baseline-replay/verification.json')
    except Exception as error:result=dict(accepted=False,error=type(error).__name__+': '+str(error),hardware_test_performed=False)
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n','utf-8');print('FLASH DELIVERY REPLAY '+('PASS'if result['accepted']else'FAILED: '+result['error']));return 0 if result['accepted']else 1

if __name__=='__main__':raise SystemExit(main())
