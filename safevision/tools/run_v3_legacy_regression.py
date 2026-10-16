"""Bind the preserved A/B regression scripts to source fingerprints."""
import argparse, hashlib, json, re, subprocess, time
from pathlib import Path
from audit_v3_raw_logs import audit_file

ROOT = Path(__file__).resolve().parents[2]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--suite', choices=['a', 'b'], required=True)
    ap.add_argument('--run-dir', required=True)
    a = ap.parse_args()
    out = Path(a.run_dir).resolve()
    if not str(out).isascii():
        raise ValueError('ASCII run directory required')
    out.mkdir(parents=True, exist_ok=True)
    script = ROOT / 'safevision/tools' / ('run_b_xsim_compat.ps1' if a.suite == 'b' else 'run_a_stage1_9_sim.ps1')
    files = {script, ROOT / 'safevision/tools/audit_v3_raw_logs.py'}
    text = script.read_text(encoding='utf-8-sig')
    if a.suite == 'b':
        original = ROOT / 'safevision/tools/run_sim.ps1'
        files |= {original, ROOT / 'safevision/tools/xsim_project.ps1'}
        src = original.read_text(encoding='utf-8-sig')
        for name in ['RTL', 'SIM']:
            block = re.search(r'\$' + name + r' = @\((.*?)\n\)', src, re.S)
            if not block:
                raise ValueError('missing list ' + name)
            files |= {(ROOT / 'safevision/verification' / p).resolve() for p in re.findall(r'"([^"]+)"', block[1])}
        block = re.search(r'\$aSources=@\((.*?)\)', text, re.S)
        files |= {ROOT / 'safevision/rtl' / p for p in re.findall(r"'([^']+)'", block[1])}
        files |= {ROOT / ('safevision/rtl/video/' + p) for p in ['video_pipeline/video_pipeline.v', 'video_timing/video_timing.v']}
    else:
        block = re.search(r'\$paths=@\((.*?)\)', text, re.S)
        files |= {ROOT / 'safevision' / p for p in re.findall(r"'([^']+)'", block[1])}
        files |= {ROOT / 'safevision/verification/unit' / (p + '.sv') for p in
                  ['tb_a_basics', 'tb_pattern_generator', 'tb_font8x16_rom', 'tb_osd_overlay', 'tb_a_graphics_frontend']}
    files |= set((ROOT / 'safevision/rtl/include').glob('*.vh'))
    files |= {ROOT / 'safevision/assets/fonts/font8x16.mem', Path(__file__)}
    def snapshot():
        return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    before = snapshot()
    (out / 'sources.sha256.json').write_text(json.dumps(before, indent=2), encoding='utf-8')
    start = time.monotonic()
    with (out / 'console.log').open('w', encoding='utf-8') as log:
        proc = subprocess.run(['powershell.exe', '-NoProfile', '-File', str(script),
                               '-RepoRoot', str(ROOT), '-RunDir', str(out / 'native')], cwd=ROOT,
                              stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    log = (out / 'console.log').read_text(encoding='utf-8', errors='replace')
    marker = 'B+A COMPILE AND B FUNCTIONAL PASS:' if a.suite == 'b' else 'PASS A stages 1-9 simulation suite'
    if a.suite == 'b':
        top_block=re.search(r'\$TBS = @\((.*?)\n\)',src,re.S)
        if not top_block:raise ValueError('missing B top manifest')
        expected=re.findall(r'"(tb_[^"]+)"',top_block[1])
        native_logs=[out/'native'/(top+'_sim.log') for top in expected]
    else:
        expected=['tb_a_basics','tb_pattern_generator','tb_font8x16_rom','tb_osd_overlay','tb_a_graphics_frontend']
        native_logs=[out/'native'/top/'xsim.log' for top in expected]
    audits=[{'top':top,**audit_file(path)} for top,path in zip(expected,native_logs)]
    passed = proc.returncode == 0 and marker in log and snapshot() == before and bool(audits) and all(x['accepted'] for x in audits)
    report = {'suite': 'legacy_' + a.suite, 'complete': passed, 'process_exit': proc.returncode,
              'source_unchanged': snapshot() == before, 'elapsed_s': round(time.monotonic()-start, 3),
              'completion_marker': marker, 'hardware_verified': False, 'raw_log_audit':audits}
    match = re.search(r'tests=(\d+) checks=(\d+)', log)
    if match:
        report.update(tests=int(match[1]), checks=int(match[2]))
    (out / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report), flush=True)
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())
