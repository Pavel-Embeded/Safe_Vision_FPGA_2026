
import argparse,hashlib,json,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--run-dir',required=True);a=ap.parse_args()
 base=Path(a.run_dir).resolve();dest=base/'source'
 if dest.exists():raise ValueError('snapshot must be a new directory')
 manifest=Path('safevision/build/manifests/v3_board_top_sim.json')
 j=json.loads((ROOT/manifest).read_text(encoding='utf-8-sig'))
 files=set(map(Path,j['sources']+j['assets']))
 files|={manifest,Path('safevision/tools/run_v3_sim.py'),Path('safevision/verification/unit/tb_v3_board_top.v')}
 files|={p.relative_to(ROOT) for p in (ROOT/'safevision/rtl/include').glob('*.vh')}
 before={p.as_posix():hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sorted(files)}
 for rel in before:
  target=dest/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/rel,target)
 after={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in before}
 if before!=after:raise RuntimeError('source changed during snapshot')
 (base/'snapshot.sha256.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
 return subprocess.run([sys.executable,str(dest/'safevision/tools/run_v3_sim.py'),'--suite','v3_board_top','--run-dir',str(base/'xsim')],check=False).returncode
if __name__=='__main__':sys.exit(main())
