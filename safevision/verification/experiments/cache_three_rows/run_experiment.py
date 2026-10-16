"""Reproduce a rejected architecture: EXPECTED_FAIL is not a production PASS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument('--run-dir', required=True)
    arguments.add_argument('--xsim-bin', default='D:/Xilinx/Vivado/2018.3/bin')
    options = arguments.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[3]
    manifest = json.loads((here / 'manifest.json').read_text())
    folder = Path(options.run_dir).resolve()
    if not str(folder).isascii():
        raise ValueError('XSim2018.3 requires ASCII output directory')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'tmp').mkdir(exist_ok=True)
    env = os.environ.copy()
    env['TMP'] = env['TEMP'] = str(folder / 'tmp')
    top = 'tb_v3_shared_memory_50'
    names = manifest['sources'] + [manifest['test_sources'][top]]
    paths = [root / name for name in names]
    tracked = paths + list((root / 'safevision/rtl/include').glob('*.vh'))
    tracked += [here / 'manifest.json', Path(__file__)]

    def snapshot():
        return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}

    before = snapshot()
    (folder / 'sources.sha256.json').write_text(json.dumps(before, indent=2))
    (folder / 'sources.prj').write_text('\n'.join('"' + p.as_posix() + '"' for p in paths))
    commands = [
        ('xvlog', ['--sv', '-d', 'SIM_FAST_TO', '-i', str(root / 'safevision/rtl/include'),
                   '--file', 'sources.prj', '--log', 'compile.log']),
        ('xelab', ['work.' + top, '-s', top, '--mt', 'off', '--timescale', '1ns/1ps', '--log', 'elab.log']),
        ('xsim', [top, '-runall', '--log', 'sim.log']),
    ]
    started = time.monotonic()
    for tool, argv in commands:
        with (folder / (tool + '.console.log')).open('w') as output:
            subprocess.run([str(Path(options.xsim_bin) / (tool + '.bat')), *argv],
                           cwd=folder, env=env, stdout=output, stderr=subprocess.STDOUT,
                           timeout=600, check=True)
    text = (folder / 'sim.log').read_text(errors='replace')
    counters = re.search(r'pixel_comparisons=(\d+) missing_pixels=(\d+) PCM=(\d+) missing_PCM=(\d+) refresh=(\d+) errors=(\d+)', text)
    if not counters:
        raise RuntimeError('missing complete pressure counters')
    comparisons, missing, pcm, audio_missing, refresh, errors = map(int, counters.groups())
    expected = (missing > 0 and errors == missing and audio_missing == 0 and pcm >= 790 and refresh > 100
                and '[FAIL] row deadline' in text and '[TB] ' + top + ' done' in text
                and '$finish called' in text and not re.search(r'(?im)^\s*(FATAL|ERROR:)', text))
    if snapshot() != before:
        raise RuntimeError('source changed during experiment')
    result = dict(status='EXPECTED_FAIL' if expected else 'UNEXPECTED_RESULT',
                  production_applicable=False, reason='three rows plus one-line lookahead miss video deadlines',
                  pixel_comparisons=comparisons, missing_pixels=missing, pcm_pairs=pcm,
                  pcm_missing=audio_missing, refresh=refresh, errors=errors,
                  elapsed_s=round(time.monotonic() - started, 3), hardware_verified=False)
    (folder / 'experiment_results.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
    return 0 if expected else 1


if __name__ == '__main__':
    raise SystemExit(main())
