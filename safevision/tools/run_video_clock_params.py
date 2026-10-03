"""Run legal-boundary and expected-rejection XSim tests. Python stdlib only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo-root', type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument('--xsim-bin', type=Path, default=Path(r'D:\Xilinx\Vivado\2018.3\bin'))
parser.add_argument('--td-root', type=Path, default=Path(r'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116'))
parser.add_argument('--run-dir', type=Path)
args = parser.parse_args()
repo = args.repo_root.resolve()
out = (args.run_dir or repo / 'safevision/verification/work_video_clock_params').resolve()
if not str(out).isascii():
    raise RuntimeError('XSim 2018.3 needs an ASCII run directory')
out.mkdir(parents=True, exist_ok=True)
temp = out / 'tmp'
temp.mkdir(exist_ok=True)
env = os.environ.copy()
env['TEMP'] = env['TMP'] = str(temp)
platform = repo / 'safevision/platform/anlogic_eg4s20_hx4s20c'
rtl = [repo / 'safevision/rtl/video/video_timing/video_timing.v']
rtl += [platform / 'rtl/clock' / name for name in
        ('reset_sync.v','clock_reset_ctrl.v','clock_gen.v','clock_video_subsystem.v')]
rtl += [platform / 'ip/pll' / (name+'.v') for name in
        ('sv_system_pll','sv_audio_pll','sv_video_vga_pll','sv_video_hd_pll')]
rtl += [args.td_root / 'sim_release/eg4' / name for name in ('eg_logic_clk.v','eg_phy_pll.v')]
benches = [repo / 'safevision/verification/unit' / name for name in
           ('tb_video_timing_params.sv','tb_clock_parameter_guards.sv')]
for path in rtl + benches:
    if not path.is_file():
        raise RuntimeError('Missing source: '+str(path))

def run_tool(name, arguments, console):
    command = subprocess.list2cmdline([str(args.xsim_bin/(name+'.bat'))]+[str(x) for x in arguments])
    # Vivado's Windows .bat wrapper tokenizes an unquoted '=' as a separator.
    # Only these locally generated numeric generic values need forced quoting.
    if name == 'xelab':
        for argument in arguments:
            value = str(argument)
            if value.startswith('CASE_ID='):
                if not value[8:].isdigit():
                    raise RuntimeError('CASE_ID must be an internally generated nonnegative integer')
                command = command.replace('--generic_top '+value, '--generic_top "'+value+'"')
    result = subprocess.run(command,
        cwd=out, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    console.write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError('%s returned %d; see %s' % (name,result.returncode,console))

run_tool('xvlog',['-i',repo/'safevision/rtl/include','--log','xvlog_verilog.log',*rtl],out/'compile_verilog.console.log')
run_tool('xvlog',['--sv','--log','xvlog_sv.log',*benches],out/'compile_sv.console.log')
results=[]
for family, top, count in (('video','tb_video_timing_params',32),('clock','tb_clock_parameter_guards',9)):
    for case_id in range(count):
        name='%s_%02d'%(family,case_id)
        case_dir=out/name
        case_dir.mkdir(exist_ok=True)
        snapshot=name+'_sim'
        run_tool('xelab',['work.'+top,'-s',snapshot,'--generic_top','CASE_ID='+str(case_id),
            '--timescale','1ns/1ps','--log',case_dir/'xelab.log'],case_dir/'xelab.console.log')
        run_tool('xsim',[snapshot,'-runall','--log',case_dir/'xsim.log'],case_dir/'xsim.console.log')
        log=(case_dir/'xsim.log').read_text(encoding='utf-8',errors='replace')
        if family=='video' and case_id<7:
            expected='legal_geometry_pass'
            ok='PASS tb_video_timing_params: CASE_ID='+str(case_id)+' ' in log and 'FAIL' not in log and 'FATAL' not in log
        elif family=='video':
            expected='invalid_geometry_rejected'
            ok='FATAL video_timing: invalid geometry or sync polarity' in log and 'invalid video geometry/polarity accepted' not in log
        else:
            expected='invalid_clock_or_reset_rejected'
            ok=any(marker in log for marker in ('[FAIL] reset_sync requires STAGES >= 2',
                '[FAIL] clock_gen VIDEO_MODE_HD must be 0 or 1',
                '[FAIL] clock_video_subsystem VIDEO_MODE_HD must be 0 or 1')) and 'invalid clock/reset parameter accepted' not in log
        if not ok:
            raise RuntimeError(name+' did not produce the specific expected result; see '+str(case_dir/'xsim.log'))
        results.append({'case':name,'expected':expected,'observed_as_expected':True,
                        'log':str(case_dir/'xsim.log')})
        print('PASS '+name+': '+expected,flush=True)

inputs=rtl+benches+[Path(__file__).resolve(),repo/'safevision/rtl/include/video_mode_defs.vh']
receipt={'result':'PASS','legal_geometry_cases':7,'invalid_geometry_cases':25,
    'invalid_clock_reset_cases':9,'cases':results,
    'inputs':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in inputs],
    'scope':'RTL parameter boundary and rejection tests; no physical hardware or formal proof'}
(out/'parameter_results.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS parameter suite: 7 legal geometries, 25 invalid geometries, 9 invalid clock/reset parameters',flush=True)
