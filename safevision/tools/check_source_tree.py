import argparse
import ast
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SUITES = ('ticker261028', 'ticker_shared261028', 'ticker_board261028', 'flexible_fs550', 'flexible_retry_fs550', 'flexible_bmp542', 'flexible_bmp_bounds551', 'spectrum539')

def check(root=ROOT):
    from v3_sources import sources, assets, native_rom_sidecars, check_gui, snapshot
    for mode in ('base', 'hd'):
        sources(root, mode)
        check_gui(root, mode)
    assets(root)
    native_rom_sidecars(root)
    snapshot(root)
    inputs = {}
    repository = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-toplevel'], capture_output=True)
    is_repository = repository.returncode == 0 and Path(repository.stdout.decode('utf-8').strip()).resolve() == root.resolve()
    if is_repository:
        tracked = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--', 'safevision'], capture_output=True, check=True)
        paths = [root / name for name in tracked.stdout.decode('utf-8').split('\0') if name]
    else: paths = list((root / 'safevision').rglob('*'))
    for path in sorted(paths):
        if not path.is_file() or '__pycache__' in path.parts or 'out' in path.parts: continue
        name = path.relative_to(root).as_posix()
        data = path.read_bytes()
        inputs[name] = hashlib.sha256(data).hexdigest()
        if path.suffix == '.py': ast.parse(data.decode('utf-8-sig'), filename=name)
        if path.suffix == '.json': json.loads(data.decode('utf-8-sig'))
        if path.suffix == '.md': raise ValueError('documentation in source tree: ' + name)
    manifests = list((root / 'safevision/build/manifests').glob('*_sim.json'))
    for path in manifests:
        data = json.loads(path.read_text('utf-8-sig'))
        names = list(data.get('sources', [])) + list(data.get('assets', [])) + list(data.get('generator_dependencies', []))
        names += list(data.get('generators', {}).values())
        for values in data.get('test_sources', {}).values(): names += [values] if isinstance(values, str) else values
        for name in names:
            target = (root / name).resolve()
            if not target.is_relative_to(root.resolve()) or not target.is_file(): raise ValueError('manifest input missing: ' + path.name + ': ' + name)
    return dict(accepted=True, files=len(inputs), simulation_manifests=len(manifests), sha256=inputs)

def simulate(suites, output, engine, xsim_bin, tops=None):
    import re
    import shutil
    output = output.resolve()
    if output.exists() or output.is_relative_to(ROOT): raise ValueError('fresh output outside source tree required')
    output.mkdir(parents=True)
    results = []
    for suite in suites:
        manifest = json.loads((ROOT / f'safevision/build/manifests/{suite}_sim.json').read_text('utf-8-sig'))
        selected = [top for top in manifest['tops'] if tops is None or top in tops]
        if not selected: raise ValueError('no selected test in suite: ' + suite)
        if engine == 'xsim':
            runner = manifest.get('native_runner', 'safevision/tools/run_v3_sim.py')
            folder = output / suite
            command = [sys.executable, '-B', str(ROOT / runner), '--suite', suite, '--run-dir', str(folder), '--xsim-bin', xsim_bin]
            if tops is not None: command += [value for top in selected for value in ('--top', top)]
            subprocess.run(command, check=True)
            record = json.loads((folder / 'results.json').read_text('utf-8-sig'))
            if not record.get('complete') or not record.get('results') or any(x['status'] != 'PASS' for x in record['results']): raise ValueError('incomplete regression: ' + suite)
            results.append(dict(suite=suite, accepted=True, tests=len(record['results'])))
        else:
            for top in selected:
                folder = output / suite / top
                folder.mkdir(parents=True)
                generator = manifest.get('generators', {}).get(top)
                if generator: subprocess.run([sys.executable, '-B', str(ROOT / generator), '--output', str(folder)], check=True)
                for name in manifest.get('assets', []): shutil.copyfile(ROOT / name, folder / Path(name).name)
                tests = manifest.get('test_sources', {}).get(top, ['safevision/verification/unit/' + top + '.sv'])
                if isinstance(tests, str): tests = [tests]
                files = list(dict.fromkeys(manifest['sources'] + tests))
                command = ['iverilog', '-g2012', '-I', str(ROOT / 'safevision/rtl/include'), '-s', top, '-o', 'sim.out']
                command += ['-D' + x for x in manifest.get('defines', ['SIM_FAST_TO'])]
                command += [str(ROOT / x) for x in files]
                subprocess.run(command, cwd=folder, check=True, timeout=300)
                run = subprocess.run(['vvp', 'sim.out'], cwd=folder, capture_output=True, text=True, timeout=manifest.get('timeouts', {}).get(top, 600))
                (folder / 'simulation.log').write_text(run.stdout + run.stderr, encoding='utf-8')
                text = run.stdout + run.stderr
                errors = re.findall(r'errors\s*=\s*(\d+)', text)
                marker = re.search(r'PASS\s+' + re.escape(top) + r'\b|\[TB\]\s*' + re.escape(top) + r'\s+done', text)
                if run.returncode or not marker or not errors or any(int(x) for x in errors) or '[PASS]' not in text or re.search(r'(?im)\[FAIL\]|\[SKIP\]|^\s*(?:FATAL|ERROR|FAIL|SKIP)\b', text): raise ValueError('HDL regression failed: ' + suite + '/' + top)
                results.append(dict(suite=suite, top=top, accepted=True))
    return results

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--simulate', action='store_true')
    parser.add_argument('--suite', action='append')
    parser.add_argument('--top', action='append')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--engine', choices=('xsim', 'iverilog'), default='xsim')
    parser.add_argument('--xsim-bin', default='D:/Xilinx/Vivado/2018.3/bin')
    args = parser.parse_args()
    before = check()
    if args.simulate:
        if args.output is None: parser.error('--output is required for simulation')
        results = simulate(args.suite or SUITES, args.output, args.engine, args.xsim_bin, args.top)
        if check()['sha256'] != before['sha256']: raise ValueError('source changed during verification')
        record = dict(before, tests=results, engine=args.engine)
        (args.output / 'verification.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in before.items() if k != 'sha256'}))

if __name__ == '__main__': main()
