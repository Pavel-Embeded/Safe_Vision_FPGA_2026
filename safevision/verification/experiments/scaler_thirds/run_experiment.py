
import argparse,json,shutil,subprocess,sys
from pathlib import Path

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--variant',choices=['first','network','delta'],required=True)
 parser.add_argument('--run-dir',type=Path,required=True)
 args=parser.parse_args();experiment=Path(__file__).resolve().parent;root=experiment.parents[3]
 out=args.run_dir.resolve()
 if not str(out).isascii():raise ValueError('XSim requires an ASCII output directory')
 if out.exists() and any(out.iterdir()):raise ValueError('use a new empty experiment directory')
 source=out/'source'
 copies={
  'safevision/tools/run_v3_sim.py':root/'safevision/tools/run_v3_sim.py',
  'safevision/rtl/video/scaler/scaler_bilinear.v':experiment/('scaler_'+args.variant+'.v'),
  'safevision/verification/unit/tb_v3_video_thirds.sv':experiment/'tb_v3_video_thirds.sv',
  'safevision/build/manifests/video_v3_thirds_sim.json':experiment/'candidate_sim.json'}
 for name,original in copies.items():
  target=source/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(original,target)
 shutil.copytree(root/'safevision/rtl/include',source/'safevision/rtl/include')
 result=subprocess.run([sys.executable,str(source/'safevision/tools/run_v3_sim.py'),'--suite','video_v3_thirds','--run-dir',str(out/'simulation')])
 record=json.loads((out/'simulation/results.json').read_text())
 if result.returncode or not record['complete']:return 1
 print('PASS: candidate arithmetic only; not production adoption, resource closure, STA or hardware proof')
 return 0

if __name__=='__main__':sys.exit(main())
