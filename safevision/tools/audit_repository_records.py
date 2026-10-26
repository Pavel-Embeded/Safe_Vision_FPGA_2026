"""Check preserved debug records, subsequent user feedback and repository links."""
from pathlib import Path, PurePosixPath
from collections import defaultdict
import argparse, gzip, hashlib, json, re, subprocess, zipfile

ROOT = Path(__file__).resolve().parents[2]
BIT_SHA = '95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e'

def require(condition, message):
    if not condition:
        raise ValueError(message)

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def relative_path(name):
    require(isinstance(name, str) and name and '\\' not in name, 'Invalid relative path')
    rel = PurePosixPath(name)
    require(not rel.is_absolute() and ':' not in name and '..' not in rel.parts, 'Escaping path: '+name)
    return rel

def safe_path(base, name):
    rel = relative_path(name)
    path = base.joinpath(*rel.parts)
    require(path.resolve().is_relative_to(base.resolve()), 'Escaping resolved path: '+name)
    for parent in [path, *path.parents]:
        if parent == base.parent:
            break
        require(not parent.is_symlink() and not (hasattr(parent, 'is_junction') and parent.is_junction()), 'Reparse path: '+name)
    return path

def git_index(root):
    raw = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--stage', '-z'])
    result = {}
    for item in raw.split(b'\0'):
        if not item:
            continue
        meta, name = item.split(b'\t', 1)
        mode, oid, stage = meta.decode().split()
        require(stage == '0', 'Unmerged file')
        result[name.decode()] = oid
    return result

def audit_acceptance(root):
    updates = read(root/'evidence/board/acceptance_updates.json')
    report = read(safe_path(root, updates['cold_boot_record']))
    require(updates['bit_sha256'] == BIT_SHA and not updates['publication_changes_rtl'], 'Acceptance identity changed')
    require(updates['current_cold_boot_status'] == 'passed_user_report', 'Unexpected acceptance status')
    require(not updates['cold_boot_machine_verified'], 'User acceptance index promoted to machine evidence')
    require(report['status'] == 'passed_user_report' and report['evidence_kind'] == 'user_report', 'User evidence type changed')
    require(report['cold_power_cycle_passed_user_report'] and not report['machine_verified'], 'User report promoted to machine evidence')
    require(report['bit_sha256_context'] == BIT_SHA, 'User report release context changed')
    require(report['cycle_count'] is None and report['serial_capture'] is None and report['startup_duration_ms'] is None, 'Unknown measurements were filled')
    frozen = read(root/'artifacts/releases/BASE_26102301_6a957b0/release.index.json')
    require(frozen['cold_power_cycle_verified'] is False, 'Frozen acceptance rewritten')

def audit(root):
    index = git_index(root)
    history = read(root/'evidence/debug_history/index.json')
    per_archive = {}
    for item in history['archives']:
        require(item['path'] not in per_archive, 'Duplicate archive')
        per_archive[item['path']] = []
    originals = set()
    for item in history['records']:
        require(item['original'] not in originals, 'Duplicate original record')
        originals.add(item['original'])
        require(item['member'] == item['original'], 'Original path changed in archive')
        require(item['archive'] in per_archive, 'Unknown archive')
        relative_path(item['member'])
        per_archive[item['archive']].append(item)
    checked = 0
    for archive in history['archives']:
        path = safe_path(root, archive['path'])
        require(path.stat().st_size == archive['bytes'] and digest(path.read_bytes()) == archive['sha256'], 'Archive checksum: '+archive['path'])
        rows = per_archive[archive['path']]
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            require(len(names) == len(set(n.casefold() for n in names)), 'Duplicate ZIP member')
            require(set(names) == {x['member'] for x in rows}, 'Archive members differ')
            require(len(rows) == archive['entries'], 'Archive record count differs')
            for row in rows:
                data = z.read(row['member'])
                require(len(data) == row['bytes'] and digest(data) == row['sha256'], 'Record checksum: '+row['original'])
                checked += 1
    require(checked == history['record_count'], 'Total record count differs')
    require(sum(x['bytes'] for x in history['records']) == history['original_bytes'], 'Original size differs')
    require(sum(x['bytes'] for x in history['archives']) == history['archive_bytes'], 'Archive size differs')

    dedup = read(root/'evidence/repository_cleanup_261026/duplicates.json')
    removed = set()
    for row in dedup['records']:
        require(row['removed'] not in removed, 'Repeated cleanup target')
        removed.add(row['removed'])
        require(row['removed'] not in index, 'Duplicate still tracked: '+row['removed'])
        require(index.get(row['retained']) == row['git_blob'], 'Retained object changed: '+row['retained'])
    require(len(removed) == dedup['removed_count'], 'Cleanup count differs')
    require(sum(x['bytes'] for x in dedup['records']) == dedup['removed_logical_bytes'], 'Cleanup bytes differ')
    protected = root/'evidence/repository_cleanup_261026/preserved_records.json.gz'
    with gzip.open(protected, 'rt', encoding='utf-8') as f:
        ledger = json.load(f)
    for row in ledger['records']:
        require(index.get(row['path']) == row['git_blob'], 'Original evidence changed or missing: '+row['path'])
    groups = defaultdict(lambda: [0, 0])
    for row in ledger['records']:
        group = '/'.join(row['path'].split('/')[:3])
        groups[group][0] += 1
        groups[group][1] += row['bytes']
    runs = read(root/'evidence/debug_history/runs.json')
    listed = {r['group']: [r['files'], r['bytes']] for r in runs['groups'] if r['storage'] == 'tracked_original'}
    require(dict(groups) == listed, 'Run catalogue differs from retained originals')

    audit_acceptance(root)

    linked = 0
    tracked_directories = {str(p) for name in index for p in PurePosixPath(name).parents}
    for name in read(root/'evidence/repository_cleanup_261026/organization.json')['documentation_files']:
        path = safe_path(root, name)
        text = path.read_text(encoding='utf-8-sig')
        require('\u2014' not in text and '\u2013' not in text, 'Dash in newly authored prose: '+name)
        text = re.sub(r'```.*?```', '', text, flags=re.S)
        for target in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text):
            target = target.strip('<>').split('#', 1)[0]
            if not target or re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', target):
                continue
            p = (path.parent/target).resolve()
            require(p.is_relative_to(root.resolve()), 'Document target escapes repository')
            relative = p.relative_to(root.resolve()).as_posix()
            require(p.exists() or relative in index or relative in tracked_directories, 'Missing document target: '+name+' -> '+target)
            linked += 1
    return dict(accepted=True, archived_original_records=checked, archives=len(history['archives']),
                protected_original_git_objects=len(ledger['records']), removed_identical_copies=len(removed),
                removed_logical_bytes=dedup['removed_logical_bytes'], archive_bytes=history['archive_bytes'],
                links_checked=linked, cold_boot_status='passed_user_report', cold_boot_machine_verified=False,
                bit_sha256=BIT_SHA, new_hardware_test_performed=False)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.repo.resolve())
    text = json.dumps(result, ensure_ascii=False, indent=2)+'\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    print(text)

if __name__ == '__main__':
    main()
