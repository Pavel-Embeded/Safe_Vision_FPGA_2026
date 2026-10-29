import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

DEFAULT_MANIFEST = None

def acceptance(root, manifest=DEFAULT_MANIFEST):
    from check_source_tree import SUITES, check
    root = root.resolve()
    before = check(root)['sha256']
    parent = Path(os.environ.get('SAFEVISION_VERIFY_OUT', str(root.parent / 'verification_runs'))).resolve()
    if parent.is_relative_to(root): raise ValueError('verification output must be outside source tree')
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='build_', dir=parent))
    target = output / 'regression'
    subprocess.run([sys.executable, '-B', str(root / 'safevision/tools/check_source_tree.py'), '--simulate', '--output', str(target)], check=True)
    result = json.loads((target / 'verification.json').read_text('utf-8'))
    if not result.get('accepted') or result.get('sha256') != before or check(root)['sha256'] != before: raise ValueError('functional verification/source mismatch')
    if {x['suite'] for x in result['tests']} != set(SUITES) or not all(x['accepted'] for x in result['tests']): raise ValueError('incomplete functional regression')
    return dict(accepted=True, engine='xsim', output=str(target), tests=result['tests'], hardware_verified=False), before

def unchanged(root, proof):
    return all((root/name).is_file() and hashlib.sha256((root/name).read_bytes()).hexdigest() == value for name, value in proof.items())
