"""Replay current BASE evidence. No new HDL/TD build or board access occurs."""
from pathlib import Path, PureWindowsPath
import argparse, hashlib, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
RELEASE = Path('artifacts/releases/BASE_26102301_6a957b0')
FORMAL_CHECK = Path('evidence/v3/ci_replay_261024/native/base/route.check')

def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def require(condition, message):
    if not condition:
        raise ValueError(message)

def frozen_reference_environment(root, out):
    """Import the already-published oracle objects, including detached commits.

    A normal GitHub clone only fetches reachable history. Frozen independent
    references are intentionally not rewritten into that development history.
    """
    legacy = 'artifacts/releases/BASE_26102004_5cff94e/'
    manifest = json.loads(subprocess.check_output(['git', '-C', str(root), 'cat-file', 'blob', 'HEAD:'+legacy+'delivery.manifest.json']))
    expected = manifest['qualification_payload_sha256'][legacy+'audit.gitobjects.pack']
    require(expected == 'eec14e285e998a58995aa51e629cd5e569142ecbeb1b48777e37ac512a33fc78', 'frozen reference pack approval changed')
    pack = out/'frozen-reference.pack'
    with pack.open('xb') as f:
        subprocess.run(['git', '-C', str(root), 'cat-file', 'blob', 'HEAD:'+legacy+'audit.gitobjects.pack'], stdout=f, check=True)
    require(sha(pack) == expected, 'frozen reference pack checksum mismatch')
    store = out/'audit-objects'
    subprocess.run(['git', 'init', '--quiet', str(store)], check=True)
    with pack.open('rb') as f:
        subprocess.run(['git', '-C', str(store), 'index-pack', '--stdin'], stdin=f, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    kind = subprocess.check_output(['git', '-C', str(store), 'cat-file', '-t', '5ece9156a28f44514b564472f4d821e72f09b77a']).decode().strip()
    require(kind == 'commit', 'independent reference commit absent from imported store')
    env = os.environ.copy()
    # This child-process setting does not edit the source checkout's .git.
    env['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = str(store/'.git/objects')
    (out/'frozen_objects.import.json').write_text(json.dumps(dict(accepted=True, pack_sha256=expected,
        detached_reference_commit_verified=True, source_repository_modified=False), indent=2)+'\n', encoding='utf-8')
    return env

def replay_timing(root):
    from check_board_timing import assess, read_report
    from check_v3_board import clock_definition_health, exception_timing, resource_gate
    from v3_resource_policy import load
    native = root / RELEASE / 'native/base'
    saved = read(native / 'timing.gate.json')
    original = [r for r in saved['reports'] if PureWindowsPath(r['path']).name == 'route.check']
    require(len(original) == 1 and sha(root / FORMAL_CHECK) == original[0]['sha256'], 'formal health report changed')
    health = read_report(root / FORMAL_CHECK)
    sta = assess(read_report(native / 'route.timing'), health)
    require(sta['gate_accepted'] and not clock_definition_health(health), 'routed timing/clock health rejected')
    require(sta['reported_path_count'] == 3320 and sta['negative_path_count'] == 0, 'routed path inventory changed')
    require(sta['minima'] == saved['sta']['minima'], 'routed minima differ from approved evidence')
    exceptions = exception_timing(read_report(native / 'after_clock_report.exceptions'))
    require(exceptions['accepted'], 'native exception timing rejected')
    resource = resource_gate(read_report(native / 'route.area'), load(root))
    require(resource['accepted'] and resource['resources'] == saved['resources'], 'resource report/policy rejected')
    return dict(accepted=True, sta=sta, exception_paths=exceptions['path_count'], resources=resource['resources'],
                scope='Reparse shipped routed reports; original full native-gate record remains checksum protected',
                fresh_TD_build_performed=False, hardware_test_performed=False)

def replay_uart(root):
    base = root / RELEASE / 'flash_install/evidence/after_flash_refresh'
    total = 0
    stages = {}
    pattern = re.compile(rb'\$C:ACK=([0-9A-F]{2}),([0-9A-F]{8})\*([0-9A-F]{2})\r\n')
    def xor(b):
        n = 0
        for x in b:
            n ^= x
        return n
    for stage in ('ready', 'configuration', 'geometries', 'periods', 'recovery', 'monitor'):
        folder = base / stage
        events = [json.loads(l) for l in (folder / 'trace.jsonl').read_text(encoding='utf-8-sig').splitlines() if l]
        require(events[-1]['kind'] == 'closed' and events[-1]['exit_code'] == 0, stage + ': missing normal close')
        require(not any(e['kind'] in ('error', 'failure_restore_attempted', 'failure_restore_error') for e in events), stage + ': failure event')
        require(len([e for e in events if e['kind'] == 'complete']) == 1, stage + ': missing completion')
        data = b''.join(bytes.fromhex(e['hex']) for e in events if e['kind'] == 'rx')
        require(data == (folder / 'rx.bin').read_bytes(), stage + ': trace/raw bytes differ')
        sent = [e for e in events if e['kind'] == 'tx']
        ack = [e for e in events if e['kind'] == 'ack']
        require(len(sent) == len(ack) > 0, stage + ': missing ACK')
        require([m[0] for m in pattern.finditer(data)] == [(e['frame']+'\r\n').encode('ascii') for e in ack], stage + ': ACK/raw mismatch')
        for tx, reply in zip(sent, ack):
            body = tx['body'].encode('ascii')
            require(tx['body'] == reply['body'] and bytes.fromhex(tx['hex']) == b'$'+body+('*%02X\r\n' % xor(body)).encode(), stage + ': transmitted frame mismatch')
            frame = (reply['frame']+'\r\n').encode('ascii')
            match = pattern.fullmatch(frame)
            require(match is not None and xor(frame[1:frame.index(b'*')]) == int(match[3], 16), stage + ': invalid checksum')
            require(int(match[1], 16) == reply['code'] == 0 and int(match[2], 16) == reply['value'], stage + ': rejected/incorrect ACK')
            if tx['body'] == 'B:DIAG=0':
                require(reply['value'] == 0x26102301, 'wrong firmware ID')
        for e in events:
            if e['kind'] == 'health':
                h = e['values']
                require(h['CACHE'] == 15 and h['WAVFALLBACK'] == 0, stage + ': invalid media')
                require(all(h[k] == 0 for k in ('LEVEL', 'INTEGRITY', 'PRESENTATION', 'RECOVERY', 'VUNDERFLOW', 'UNDERFLOW', 'OVERFLOW', 'FAULT')), stage + ': health error')
        stages[stage] = len(ack)
        total += len(ack)
    require(total == 5016, 'UART ACK inventory changed')
    return dict(accepted=True, validated_ack_frames=total, stages=stages,
                scope='Replay existing recorded UART bytes; no live board test', hardware_test_performed=False)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, default=ROOT)
    ap.add_argument('--run-dir', type=Path, required=True)
    ap.add_argument('--node', default='node')
    a = ap.parse_args()
    root, out = a.repo.resolve(), a.run_dir.resolve()
    require(__debug__, 'Python assertions must remain enabled')
    require(str(out).isascii() and not out.exists() and not out.is_relative_to(root) and not root.is_relative_to(out), 'use a fresh separate ASCII output directory')
    out.mkdir(parents=True)
    result = dict(accepted=False, firmware='26102301', fresh_HDL_simulation_performed=False,
                  fresh_TD_build_performed=False, hardware_test_performed=False, github_write_performed=False)
    try:
        p = subprocess.run([a.node, str(root/'safevision/tools/verify_base_release.mjs')], capture_output=True, text=True)
        require(p.returncode == 0, 'delivery byte check failed: '+p.stderr[-2000:])
        byte_check = json.loads(p.stdout)
        (out/'byte_verification.json').write_text(json.dumps(byte_check, indent=2)+'\n', encoding='utf-8')
        env = frozen_reference_environment(root, out)
        command = [sys.executable, '-B', str(root/'safevision/tools/audit_v3_four_features.py'), '--repo', str(root), '--source-repo', str(root), '--manifest', 'evidence/v3/four_features_261020/acceptance.json', '--output', str(out/'qualification.replay.json')]
        with (out/'qualification.console.log').open('wb') as log:
            code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env).returncode
        require(code == 0, 'current full qualification replay failed; inspect qualification.console.log')
        functional = read(out/'qualification.replay.json')
        require(functional['accepted'] and functional['positive_unique_tops'] == 303 and functional['strict_normal_ending_mutants'] == 221 and functional['physical_inputs'] == 206, 'current qualification inventory rejected')
        sta, uart = replay_timing(root), replay_uart(root)
        for name, value in (('sta.replay.json', sta), ('uart.replay.json', uart)):
            (out/name).write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')
        result.update(accepted=True, physical_inputs=206, positive_unique_tops=303, semantic_negative_controls=221,
                      source_build_commit=functional['source_build_commit'], bit_sha256=byte_check['bit_sha256'],
                      timing_reported_paths=sta['sta']['reported_path_count'], validated_ack_frames=uart['validated_ack_frames'])
    except Exception as e:
        result['error'] = type(e).__name__+': '+str(e)
    (out/'verification.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print('CURRENT BASE EVIDENCE REPLAY '+('PASS' if result['accepted'] else 'FAILED: '+result['error']), flush=True)
    return 0 if result['accepted'] else 1

if __name__ == '__main__':
    sys.exit(main())
