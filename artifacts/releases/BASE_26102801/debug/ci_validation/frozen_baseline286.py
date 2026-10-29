from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

w = Path(__file__).resolve().parent
root = Path('D:/Codex/SafeVision_BASE_CURRENT/repo')
out = w / os.environ.get('SAFEVISION_BASELINE_RUN', 'frozen_baseline286')
git = 'D:/Git/mingw64/bin/git.exe'
assert not out.exists()
head = subprocess.check_output([git, '-C', str(root), 'rev-parse', 'HEAD']).decode().strip()
assert head == '09faac2e8fa718c9f92ef4a5013b68003ec8afe6'
assert not subprocess.check_output([git, '-C', str(root), 'status', '--porcelain']).strip()
out.mkdir()
environment = os.environ.copy()
environment['PATH'] = str(Path(git).parent) + os.pathsep + environment.get('PATH', '')
environment['TEMP'] = environment['TMP'] = str(w / 'tmp')
environment['PYTHONIOENCODING'] = 'utf-8'
commands = [[name] for name in ('test_base_delivery.py', 'test_current_base_ci.py', 'test_repository_records.py')]
commands += [['audit_repository_records.py', '--output', str(out / 'records.json')], ['verify_current_base_ci.py', '--run-dir', str(out / 'replay')]]
results = []
for arguments in commands:
    log = out / (arguments[0] + '.log')
    with log.open('w', encoding='utf-8') as stream:
        completed = subprocess.run([sys.executable, '-B', str(root / 'safevision/tools' / arguments[0]), *arguments[1:]], cwd=root, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    results.append(dict(tool=arguments[0], exit_code=completed.returncode, log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
    assert completed.returncode == 0, str(log)
assert not subprocess.check_output([git, '-C', str(root), 'status', '--porcelain']).strip()
verification = json.loads((out / 'replay/verification.json').read_text('utf-8'))
assert verification['accepted'] and verification['physical_inputs'] == 206 and verification['positive_unique_tops'] == 303 and verification['semantic_negative_controls'] == 221
result = dict(accepted=True, frozen_commit=head, tools=results, verification_sha256=hashlib.sha256((out/'replay/verification.json').read_bytes()).hexdigest(), hardware_test_performed=False, github_uploaded=False)
(out / 'stage.json').write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
print('ALL FIVE FROZEN BASELINE TOOLS AND FULL ORIGINAL REPLAY PASS')
