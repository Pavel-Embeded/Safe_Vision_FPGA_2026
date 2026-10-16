"""Inventory immutable test evidence against the CURRENT source tree.

A historical PASS is not a current PASS after any recorded source changes.
This inventory never substitutes for routed STA, bit generation or hardware.
"""
import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from audit_v3_raw_logs import audit_file

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_result(path, root):
    record = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(record, dict):
        raise ValueError('not a simulation result object')
    entries = []
    legacy = str(record.get('suite', '')).startswith('legacy_')
    tests = record.get('results', [])
    if not isinstance(tests, list):
        raise ValueError('simulation results must be a list')
    if legacy:
        tests = [{'top': record['suite']+'_suite',
                  'status': 'PASS' if record.get('complete') is True
                            and record.get('process_exit') == 0
                            and record.get('source_unchanged') is True else 'FAIL',
                  'checks': record.get('checks'), 'elapsed_s': record.get('elapsed_s')}]
    for test in tests:
        top_name = test.get('top', '')
        source_file = (path.parent if legacy else path.parent / top_name) / 'sources.sha256.json'
        changed = []
        external = []
        if source_file.is_file():
            sources = json.loads(source_file.read_text(encoding='utf-8'))
            if not isinstance(sources, dict) or not sources:
                raise ValueError('source manifest must be a nonempty object')
            if not all(isinstance(name,str) and isinstance(expected,str)
                       and re.fullmatch(r'[0-9a-f]{64}',expected)
                       for name,expected in sources.items()):
                raise ValueError('source manifest requires named SHA-256 values')
            generated = {}
            if any(name.startswith('generated:') for name in sources):
                suite = record.get('suite', '')
                if not isinstance(suite, str) or not re.fullmatch(r'[A-Za-z0-9_]+', suite):
                    raise ValueError('generated assets require a declared suite')
                manifest_name = f'safevision/build/manifests/{suite}_sim.json'
                manifest_path = root / manifest_name
                if manifest_name not in sources or not manifest_path.is_file():
                    raise ValueError('generated assets require the suite source manifest')
                manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
                declared = manifest.get('generated_assets', [])
                if not isinstance(declared, list) or not all(isinstance(n, str) for n in declared):
                    raise ValueError('invalid generated asset declaration')
                after_path = source_file.parent / 'sources.after.sha256.json'
                if not after_path.is_file():
                    raise ValueError('missing after-run generated asset fingerprint')
                if json.loads(after_path.read_text(encoding='utf-8')) != sources:
                    changed.append('GENERATED/SOURCE before-after fingerprint drift')
                for name in (n for n in sources if n.startswith('generated:')):
                    relative = Path(name[len('generated:'):])
                    candidate = (source_file.parent / relative).resolve()
                    if relative.is_absolute() or '..' in relative.parts or not candidate.is_relative_to(source_file.parent.resolve()):
                        raise ValueError('generated asset escaped its run directory')
                    if relative.as_posix() not in declared:
                        raise ValueError('undeclared generated asset: '+name)
                    generated[name] = candidate
            for filename, expected in sources.items():
                if filename in generated:
                    candidate = generated[filename]
                    if not candidate.is_file() or sha(candidate) != expected:
                        changed.append(filename)
                    continue
                candidate = Path(filename)
                current = (root / candidate).resolve()
                # Prototype runners may record absolute scratch-source paths.
                # Comparing such a path with itself proves a frozen experiment,
                # never identity with the current production repository.
                if not current.is_relative_to(root.resolve()):
                    external.append(filename)
                if not current.is_file() or sha(current) != expected:
                    changed.append(filename)
        else:
            changed.append('MISSING sources.sha256.json')
        reported_pass = test.get('status') == 'PASS'
        if legacy:
            if record.get('suite')=='legacy_b':
                raw_paths=sorted((path.parent/'native').glob('*_sim.log'))
                wanted=record.get('tests',0)
            else:
                names=['tb_a_basics','tb_pattern_generator','tb_font8x16_rom','tb_osd_overlay','tb_a_graphics_frontend']
                raw_paths=[path.parent/'native'/n/'xsim.log' for n in names];wanted=len(names)
            raw_audit={'accepted':bool(raw_paths) and len(raw_paths)==wanted,'tests':[audit_file(p) for p in raw_paths]}
            raw_audit['accepted']=raw_audit['accepted'] and all(x['accepted'] for x in raw_audit['tests'])
        else:
            raw_audit=audit_file(path.parent/top_name/'sim.log')
        passed = reported_pass and raw_audit['accepted']
        state = ('RAW_LOG_REJECTED' if reported_pass and not raw_audit['accepted'] else
                 ('EXTERNAL_SNAPSHOT_PASS' if passed and not changed and external else
                 'CURRENT_PASS' if passed and not changed else
                 'STALE_PASS' if passed else 'FAIL_OR_INCOMPLETE'))
        entries.append({
            'top': top_name, 'state': state, 'changed_sources': changed, 'raw_log_audit':raw_audit,
            'external_snapshot_sources': external,
            'recorded_status': test.get('status'),
            'checks': test.get('checks'),
            'data_comparisons': test.get('data_comparisons'),
            'elapsed_s': test.get('elapsed_s'),
            'raw_log': str(path.parent / 'console.log' if legacy else path.parent / top_name / 'sim.log'),
            'source_manifest': str(source_file),
        })
    return {
        'run': str(path.parent), 'suite': record.get('suite'),
        'complete': record.get('complete') is True,
        'all_current_pass': bool(entries) and record.get('complete') is True
                            and all(e['state'] == 'CURRENT_PASS' for e in entries),
        'result_sha256': sha(path), 'tests': entries,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repo', type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.repo.resolve()
    runs = []
    for path in sorted(args.runs.resolve().rglob('results.json')):
        try:
            runs.append(inspect_result(path, root))
        except (OSError, ValueError, TypeError) as error:
            runs.append({'run': str(path.parent), 'all_current_pass': False,
                         'inventory_error': str(error)})
    git = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'],
                         capture_output=True, text=True, check=True)
    dirty = subprocess.run(['git', '-C', str(root), 'status', '--porcelain'],
                           capture_output=True, text=True, check=True)
    inventory = {
        'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'repository': str(root), 'source_commit': git.stdout.strip(),
        'working_tree_dirty': bool(dirty.stdout),
        'runs': runs, 'release_ready': False,
        'release_note': 'Inventory only. Require all mandatory suites, both routed '
                        'STA/resource gates, reproducible bitstreams and explicit '
                        'hardware acceptance before claiming their respective results.',
        'hardware_verified': False,
        'encrypted_vendor_behavior_verified': False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(inventory, ensure_ascii=False, indent=2)+'\n',
                           encoding='utf-8')
    current = sum(r.get('all_current_pass', False) for r in runs)
    print(json.dumps({'runs': len(runs), 'current_pass_runs': current,
                      'output': str(args.output), 'release_ready': False}))


if __name__ == '__main__':
    main()
