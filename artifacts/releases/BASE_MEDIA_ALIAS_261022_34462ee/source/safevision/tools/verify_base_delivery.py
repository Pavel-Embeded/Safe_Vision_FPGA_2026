"""Verify the published BASE checkout and replay its unchanged qualification.

No TD, JTAG, serial, network, or hardware writes are performed. The auxiliary
Git object store contains only the original objects read by the auditors; it
is deliberately not a clone of the unrelated development history.
"""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, os, shutil, subprocess, sys, zipfile

ROOT = Path(__file__).resolve().parents[2]
RELEASE = Path('artifacts/releases/BASE_26102004_5cff94e')

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inside(root, name):
    p = PurePosixPath(name)
    if p.is_absolute() or '\\' in name or ':' in name or '..' in p.parts:
        raise ValueError('unsafe relative path: ' + name)
    target = (root / name).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError('path escaped delivery: ' + name)
    return target

def check_checkout(root):
    index = read(root / RELEASE / 'delivery.manifest.json')
    if index['schema'] != 1 or index['qualified_modes'] != ['base']:
        raise ValueError('unsupported BASE delivery manifest')
    for group in ('qualification_payload_sha256', 'published_source_sha256', 'board_evidence_sha256', 'delivery_files_sha256'):
        for name, digest in index[group].items():
            if sha(inside(root, name)) != digest:
                raise ValueError('delivery SHA-256 mismatch: ' + name)
    bit = root / RELEASE / 'SafeVision_BASE_5cff94e.bit'
    if sha(bit) != index['bit_sha256'] or bit.stat().st_size != 644770:
        raise ValueError('incorrect BASE bitstream')
    return index

def extract(archive, destination):
    with zipfile.ZipFile(archive) as z:
        total = 0
        seen = set()
        for item in z.infolist():
            path = inside(destination, item.filename)
            folded = item.filename.casefold()
            if folded in seen or ((item.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError('duplicate or symbolic-link ZIP member')
            seen.add(folded)
            total += item.file_size
            if total > 1024 * 1024 * 1024:
                raise ValueError('qualification archive is unexpectedly large')
            if item.is_dir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with z.open(item) as src, path.open('xb') as dst:
                    shutil.copyfileobj(src, dst)

def execute(args, cwd=None, **kwargs):
    p = subprocess.run(args, cwd=cwd, capture_output=True, **kwargs)
    if p.returncode:
        raise RuntimeError(str(args[0]) + ' failed: ' + p.stderr.decode(errors='replace')[-2000:])
    return p.stdout

def verify(root, run):
    if not __debug__:
        raise ValueError('assertions must remain enabled; do not use python -O')
    if os.name != 'nt':
        raise ValueError('original Windows TD path receipts require Windows for full replay')
    if not str(run).isascii() or run == root or run.is_relative_to(root) or root.is_relative_to(run):
        raise ValueError('use a separate, new ASCII run directory')
    if run.exists():
        raise ValueError('run directory must not already exist')
    manifest_sha = sha(root / RELEASE / 'delivery.manifest.json')
    index = check_checkout(root)
    run.mkdir(parents=True)
    package = run / 'qualification'
    package.mkdir()
    extract(root / RELEASE / 'qualification.zip', package)
    objects = run / 'audit-objects'
    execute(['git', 'init', '--quiet', str(objects)])
    with (root / RELEASE / 'audit.gitobjects.pack').open('rb') as f:
        execute(['git', '-C', str(objects), 'index-pack', '--stdin'], stdin=f)
    source = package / 'source'
    # Attribute lookup must use the original source's explicit text filters.
    execute(['git', '-C', str(objects), 'config', 'core.worktree', str(source)])
    execute(['git', '-C', str(objects), 'config', 'core.autocrlf', 'false'])
    execute(['git', '-C', str(objects), 'update-ref', 'refs/heads/approved', index['approval_source_commit']])
    execute(['git', '-C', str(objects), 'symbolic-ref', 'HEAD', 'refs/heads/approved'])
    (source / '.git').write_text('gitdir: ' + (objects / '.git').as_posix() + '\n', encoding='utf-8')
    output = run / 'qualification.replay.json'
    # Git --path filtering is relative to the current working tree. Running
    # -C on the external metadata directory can find check-attr rules yet
    # bypass their clean filter in hash-object. Always enter the source tree.
    command = [sys.executable, '-B', str(package / 'verify_payload.py'), '--source-repo', str(source), '--output', str(output)]
    with (run / 'qualification.console.log').open('wb') as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if process.returncode or not output.is_file() or not read(output)['accepted']:
        raise ValueError('unchanged full qualification replay failed; see qualification.console.log')
    # Recheck published bytes after replay; immutable qualification stays intact.
    if sha(root / RELEASE / 'delivery.manifest.json') != manifest_sha:
        raise ValueError('delivery manifest changed during replay')
    check_checkout(root)
    result = dict(accepted=True, qualified_modes=['base'], physical_inputs=198,
                  positive_unique_tops=288, semantic_negative_controls=202,
                  approval_source_commit=index['approval_source_commit'],
                  design_build_commit=index['design_build_commit'],
                  bit_sha256=index['bit_sha256'], frozen_source=str(source),
                  audit_object_store=str(objects), fresh_TD_build_performed=False,
                  hardware_test_performed=False, github_write_performed=False)
    (run / 'verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--repo', type=Path, default=ROOT)
    ap.add_argument('--run-dir', type=Path)
    ap.add_argument('--checksums-only', action='store_true', help='Integrity only; does not approve functional/STA replay')
    a = ap.parse_args()
    try:
        if a.checksums_only:
            check_checkout(a.repo.resolve())
            print('CHECKOUT SHA-256 PASS (full qualification was not replayed)', flush=True)
        else:
            if a.run_dir is None:
                raise ValueError('--run-dir is required for full qualification replay')
            verify(a.repo.resolve(), a.run_dir.resolve())
            print('BASE FULL QUALIFICATION REPLAY PASS; hardware acceptance remains separately recorded', flush=True)
        return 0
    except Exception as e:
        print('BASE DELIVERY REJECTED: ' + type(e).__name__ + ': ' + str(e), file=sys.stderr, flush=True)
        return 1

if __name__ == '__main__':
    sys.exit(main())
