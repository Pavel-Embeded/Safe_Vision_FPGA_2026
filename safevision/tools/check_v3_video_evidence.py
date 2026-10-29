
import hashlib
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[2]
    evidence = json.loads((root / 'docs/v3/video_validation.json').read_text())
    errors = []
    for name, expected in evidence['verified_source_sha256'].items():
        path = root / name
        actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else 'MISSING'
        if actual != expected:
            errors.append(name)
    if errors:
        raise SystemExit('STALE_VIDEO_EVIDENCE: rerun affected suites before refreshing index: ' + ', '.join(errors))
    print(f"PASS: {len(evidence['verified_source_sha256'])} current RTL/asset hashes match normal-ending video evidence")


if __name__ == '__main__':
    main()
