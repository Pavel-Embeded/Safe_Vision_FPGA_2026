"""Bind release simulation acceptance and its complete inputs to the source commit."""
import hashlib,json
from pathlib import Path
from audit_v3_resource_checkpoint import audit,within

DEFAULT_MANIFEST=Path('evidence/v3/resource_113_20261016/acceptance.json')

def acceptance(root,manifest=DEFAULT_MANIFEST):
 if not __debug__:raise RuntimeError('functional release audit requires Python assertions enabled')
 root=root.resolve();manifest=within(root,manifest)
 result=audit(root,manifest)
 if not result['accepted']:raise ValueError('functional acceptance rejected')
 index=json.loads(manifest.read_text(encoding='utf-8'))
 files={manifest,root/'evidence/v3/current_100_20261016/selected_acceptance.json'}
 for row in index['positive_tests']+index['negative_controls']:
  folder=within(root,row['evidence'])
  # Curated case folders contain only provenance, raw logs, exact mutant bytes
  # and generated vectors. Include every file so none can drift after approval.
  files.update(p for p in folder.rglob('*') if p.is_file())
  fingerprints=json.loads((folder/'sources.sha256.json').read_text(encoding='utf-8'))
  for name in fingerprints:
   if not name.startswith('generated:'):files.add(within(root,name))
 hashes={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
 return {'accepted':True,'manifest':manifest.relative_to(root).as_posix(),'positive_native_tests':result['positive_unique_native_tests'],'strict_normal_ending_mutants':result['strict_normal_ending_mutants'],'committed_proof_dependencies':len(hashes)},hashes

def unchanged(root,hashes):
 return all((root/name).is_file() and hashlib.sha256((root/name).read_bytes()).hexdigest()==value for name,value in hashes.items())
