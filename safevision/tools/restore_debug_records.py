"""List archived runs; restore exact records into an empty folder with --apply."""
from pathlib import Path
import argparse, json, subprocess, zipfile
from audit_repository_records import ROOT, digest, read, require, safe_path

def output_directory(requested):
    requested = requested.absolute()
    for path in [requested, *requested.parents]:
        require(not path.is_symlink() and not (hasattr(path, 'is_junction') and path.is_junction()), 'Output resolves through a link')
    # Windows short names can expand during resolve without being links.
    return requested.resolve()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--group')
    parser.add_argument('--duplicates', action='store_true')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    index = read(ROOT/'evidence/debug_history/index.json')
    if args.list:
        for row in index['archives']:
            print(row['group'], row['entries'], row['bytes'])
        return
    require(bool(args.group) != args.duplicates, 'Choose --group or --duplicates')
    require(args.output is not None, '--output is required')
    output = output_directory(args.output)
    require(not output.exists() or output.is_dir() and not any(output.iterdir()), 'Output must be empty')
    if args.duplicates:
        manifest = read(ROOT/'evidence/repository_cleanup_261026/duplicates.json')
        rows = manifest['records']
        for row in rows:
            safe_path(output, row['removed'])
        print(json.dumps(dict(apply=args.apply, records=len(rows), bytes=sum(x['bytes'] for x in rows), output=str(output)), indent=2))
        if not args.apply:
            return
        for row in rows:
            source = safe_path(ROOT, row['retained'])
            data = source.read_bytes()
            if digest(data) != row['sha256']:
                data = subprocess.check_output(['git','-C',str(ROOT),'cat-file','blob',row['git_blob']])
            require(len(data) == row['bytes'] and digest(data) == row['sha256'], 'Source identity differs: '+row['retained'])
            target = safe_path(output, row['removed'])
            target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb') as f:
                f.write(data)
        print('Duplicate payload restore passed')
    else:
        archives = [a for a in index['archives'] if a['group'] == args.group]
        require(len(archives) == 1, 'Unknown group; use --list')
        archive = archives[0]
        rows = [r for r in index['records'] if r['archive'] == archive['path']]
        path = safe_path(ROOT, archive['path'])
        require(digest(path.read_bytes()) == archive['sha256'], 'Archive checksum differs')
        for row in rows:
            safe_path(output, row['member'])
        print(json.dumps(dict(apply=args.apply, group=args.group, records=len(rows), bytes=sum(x['bytes'] for x in rows), output=str(output)), indent=2))
        if not args.apply:
            return
        with zipfile.ZipFile(path) as z:
            for row in rows:
                data = z.read(row['member'])
                require(len(data) == row['bytes'] and digest(data) == row['sha256'], 'Record checksum differs')
                target = safe_path(output, row['member'])
                target.parent.mkdir(parents=True,exist_ok=True)
                with target.open('xb') as f:
                    f.write(data)
        print('Debug record restore passed')

if __name__ == '__main__':
    main()
