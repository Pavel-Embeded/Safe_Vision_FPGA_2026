import hashlib,importlib.util,json,os,re,subprocess,sys
from pathlib import Path
import argparse
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description='Standalone SDRAM probe, not the final application. No bitgen or GitHub upload.')
parser.add_argument('--run-dir',required=True,type=Path);args=parser.parse_args()
RUN=ROOT/'safevision/platform/anlogic_eg4s20_hx4s20c/project/adapter_writebus_26101726'
SRC=ROOT;OUT=args.run_dir.resolve();assert str(OUT).isascii()
assert not OUT.exists() or not any(OUT.iterdir()),'New empty isolated output directory required'
OUT.mkdir(parents=True,exist_ok=True)
exe=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
sys.path.insert(0,str(ROOT/'safevision/tools'))
from check_board_timing import assess,read_report
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=json.loads((RUN/'native.sources.json').read_text())
files+=['safevision/platform/anlogic_eg4s20_hx4s20c/ip/sdram/global_def.v']
before={name:sha(SRC/name) for name in files};before.update({name:sha(RUN/name) for name in ('probe.adc','probe.sdc')})
(OUT/'sources.sha256.json').write_bytes((json.dumps(before,indent=2)+'\n').encode())
ordered=json.loads((RUN/'native.sources.json').read_text())
body='''import_device eagle_s20.db -package EG4S20BG256
set_param rtl min_control_set 3
set_param rtl min_ripple_len 16
set_param rtl infer_fsm off
set_param gate map_mode area_prior
set_param gate pack_effort high
set_param place effort high
set_param route effort routability
set_param route timing on
set_param route fix_hold on
read_hdl -file {'''+ ' '.join((SRC/n).as_posix() for n in ordered)+'''} -include_dir {'''+(SRC/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/sdram').as_posix()+'''} -top sv_v3_adapter_writebus_trace
read_adc {'''+(RUN/'probe.adc').as_posix()+'''}
optimize_rtl
read_sdc {'''+(RUN/'probe.sdc').as_posix()+'''}
optimize_gate
legalize_phy_inst
write_verilog gate.netlist.v
report_area -io_info -file gate.area
clear_sdc
read_sdc {'''+(RUN/'probe.sdc').as_posix()+'''}
update_timing -mode basic
if {[llength [get_nets {probe_common_rst_n}]]==0} {error "missing named asynchronous reset root"}
place
route
fix_hold
update_timing -mode final
report_timing_summary -ep_num 10000 -path_num 1 -file route.timing
report_timing_status -file route.status
report_timing_exception -file route.exceptions
check_design
check_timing -verbose -file route.check
report_area -io_info -file route.area
export_sdc -file route.derived.sdc
export_db route.db
'''
def invoke(name,body):
 tcl=OUT/(name+'.tcl');tcl.write_bytes(('cd {'+OUT.as_posix()+'}\nif {[catch {\n'+body+'\n} err]} {puts stderr "PROBE FAILED: $err";exit 1}\nputs "PROBE '+name.upper()+' COMPLETE"\nexit 0\n').encode())
 with (OUT/(name+'.console.log')).open('wb') as log:rc=subprocess.run([str(exe),tcl.as_posix()],stdout=log,stderr=subprocess.STDOUT,timeout=900).returncode
 text=(OUT/(name+'.console.log')).read_text(encoding='utf-8',errors='replace')
 assert rc==0 and 'PROBE '+name.upper()+' COMPLETE' in text and not re.search(r'PROBE FAILED|\bERROR:|multiple drivers?',text,re.I),name
invoke('route',body)
db=sha(OUT/'route.db')
invoke('final','import_db {'+(OUT/'route.db').as_posix()+'}\nclear_sdc\nread_sdc {'+(RUN/'probe.sdc').as_posix()+'}\nupdate_timing -mode final\nreport_timing_summary -ep_num 10000 -path_num 1 -file final.timing\nreport_timing_status -file final.status\nreport_timing_exception -file final.exceptions\ncheck_timing -verbose -file final.check\nreport_clock_summary -levels 20 -expand_buckets -debug -file final.clocks\n')
assert db==sha(OUT/'route.db')
verdicts=[]
for phase in ('route','final'):
 v=assess(read_report(OUT/(phase+'.timing')),read_report(OUT/(phase+'.check')))
 verdicts.append(v);print(json.dumps({'phase':phase,'assessment':v},ensure_ascii=False),flush=True)
 assert v['timing_passed'] and all(x['reported_min_ns'] is not None for x in v['minima'].values())
assert all(sha((RUN/name) if name in ('probe.adc','probe.sdc') else SRC/name)==digest for name,digest in before.items())
result=dict(profile='MEM50_SDRAM_PLUS8NS_PASSIVE_APP_WRITE_PAYLOAD_OBSERVER',diagnostic_only=True,production_application=False,
 bitstream_generated=False,hardware_verified=False,source_sha256=before,routed_db_sha256=db,assessments=verdicts,github_upload_performed=False)
(OUT/'native.acceptance.json').write_bytes((json.dumps(result,indent=2,ensure_ascii=False)+'\n').encode('utf-8'))
print('PROBE NATIVE ACCEPTANCE COMPLETE',flush=True)
