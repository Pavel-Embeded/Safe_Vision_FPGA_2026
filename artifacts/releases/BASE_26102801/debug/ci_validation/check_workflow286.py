from pathlib import Path
import ast
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import yaml

w = Path(__file__).resolve().parent
workflow = w / 'wav_reject_barrier_source/.github/workflows/base-qualification.yml'
raw = workflow.read_bytes()
document = yaml.safe_load(raw)
jobs = document['jobs']
baseline = jobs['frozen_baseline']
current = jobs['audit']
assert current['needs'] == 'frozen_baseline' and current['if'] == 'always()'
assert baseline['runs-on'] == current['runs-on'] == 'windows-latest'
checkouts = [s for s in baseline['steps'] if s.get('uses', '').startswith('actions/checkout@')]
assert len(checkouts) == 1 and checkouts[0]['with']['ref'] == '09faac2e8fa718c9f92ef4a5013b68003ec8afe6'
assert checkouts[0]['with']['fetch-depth'] == 0
baseline_run = next(s['run'] for s in baseline['steps'] if s.get('name') == 'Verify all frozen baseline checks')
for tool in ('test_base_delivery.py', 'test_current_base_ci.py', 'test_repository_records.py', 'audit_repository_records.py', 'verify_current_base_ci.py'):
    assert tool in baseline_run
current_runs = '\n'.join(s.get('run', '') for s in current['steps'])
for tool in ('test_ticker_archive261028.py', 'test_ticker_uart261028.py', 'audit_repository_records.py'):
    assert tool in current_runs
gate = current['steps'][0]
assert gate['env']['BASELINE_RESULT'] == '${{ needs.frozen_baseline.result }}'
assert 'throw' in gate['run'] and "-ne 'success'" in gate['run']
run = next(s['run'] for s in current['steps'] if s.get('name') == 'Replay current ticker delivery')
snippet = run.split("@'\n", 1)[1].split("\n'@", 1)[0]
ast.parse(snippet)
assert 'from verify_ticker_ci import verify' in snippet
assert 'result = verify(root, out)' in snippet
assert '0 if result[\'accepted\'] else 1' in snippet
rows = []
ps = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
with tempfile.TemporaryDirectory(prefix='workflow286-', dir=w/'tmp') as scratch:
    scratch = Path(scratch)
    gate_script = scratch / 'baseline_gate.ps1'
    gate_script.write_text(gate['run'], 'utf-8-sig')
    for status in ('success', 'failure', 'cancelled', 'skipped', 'unknown', ''):
        env = os.environ.copy()
        env['BASELINE_RESULT'] = status
        process = subprocess.run([ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(gate_script)], env=env, capture_output=True)
        assert (process.returncode == 0) == (status == 'success')
        rows.append(dict(case='baseline_' + (status or 'empty'), accepted=(process.returncode == 0), expected_acceptance=(status == 'success'), exit_code=process.returncode))
    for behavior in ('pass', 'reject', 'raise', 'existing_output'):
        root = scratch / behavior
        tools = root / 'safevision/tools'
        tools.mkdir(parents=True)
        if behavior in ('pass', 'existing_output'):
            fake = "def verify(root, out):\n return dict(accepted=True, sentinel='stub_only_no_hardware_claim')\n"
        elif behavior == 'reject':
            fake = "def verify(root, out):\n return dict(accepted=False, error='deliberate verification refusal')\n"
        else:
            fake = "def verify(root, out):\n raise ValueError('deliberate exception')\n"
        (tools / 'verify_ticker_ci.py').write_text(fake, 'utf-8')
        runner_temp = root / 'runner_temp'
        runner_temp.mkdir()
        if behavior == 'existing_output':
            (runner_temp / 'safevision-base-audit').mkdir()
        env = os.environ.copy()
        env['RUNNER_TEMP'] = str(runner_temp)
        env['PYTHONIOENCODING'] = 'utf-8'
        process = subprocess.run([sys.executable, '-B', '-'], input=snippet.encode(), cwd=root, env=env, capture_output=True)
        assert (process.returncode == 0) == (behavior == 'pass')
        receipt = runner_temp / 'safevision-base-audit/verification.json'
        if receipt.exists():
            assert json.loads(receipt.read_text())['accepted'] == (behavior == 'pass')
        rows.append(dict(case='current_' + behavior, accepted=(process.returncode == 0), expected_acceptance=(behavior == 'pass'), exit_code=process.returncode))
result = dict(accepted=True, workflow_sha256=hashlib.sha256(raw).hexdigest(), frozen_baseline_ref=checkouts[0]['with']['ref'], preserved_frozen_tools=5, current_tests_and_audit_retained=True, required_audit_runs_after_any_baseline_result=True, synthetic_cases=rows, actual_current_hardware_verification_performed=False, scope='Actual workflow shell gate and Python wrapper, with explicit synthetic verifier stubs')
(w / 'workflow_checks286.json').write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
print('WORKFLOW STRUCTURE AND TEN EXECUTED FAILURE-PROPAGATION CASES PASS')
