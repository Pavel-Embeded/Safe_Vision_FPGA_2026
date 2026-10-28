"""Recheck copied bitstream, current sources and full proof before SRAM download."""
from pathlib import Path
import argparse,json
from verify_ticker_ci import ROOT,RELEASE,offline,require
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--package',type=Path);ap.add_argument('--run-dir',type=Path,required=True);a=ap.parse_args()
 root=a.repo.resolve();release=(a.package or root/RELEASE).resolve();out=a.run_dir.resolve()
 require(release.is_relative_to(root),'package outside selected project');require(not out.exists()and str(out).isascii()and not out.is_relative_to(root),'fresh separate ASCII output required');out.mkdir(parents=True)
 try:r=offline(root,release,out)
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e),hardware_test_performed=False)
 (out/'verification.json').write_text(json.dumps(r,indent=2)+'\n','utf-8');print('TICKER COPIED PACKAGE '+('PASS'if r['accepted']else'REJECTED: '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
