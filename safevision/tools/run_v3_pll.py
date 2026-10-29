
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--run-dir',required=True);a=ap.parse_args()
 base=Path(a.run_dir).resolve();base.mkdir(parents=True,exist_ok=True)
 if not str(base).isascii():raise ValueError('ASCII output required')
 td=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116')
 xb=Path('D:/Xilinx/Vivado/2018.3/bin')
 model=[td/'sim_release/eg4/eg_logic_clk.v',td/'sim_release/eg4/eg_phy_pll.v']
 source=ROOT/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_v3_memory_pll.v'
 tb=ROOT/'safevision/verification/unit/tb_v3_pll.v'
 files=model+[source,tb,Path(__file__)]
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
 (base/'sources.sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
 results=[]
 for case in ('baseline','phase_negative'):
  folder=base/case;folder.mkdir(exist_ok=True);(folder/'tmp').mkdir(exist_ok=True)
  env=os.environ.copy();env['TEMP']=env['TMP']=str(folder/'tmp')
  candidate=source
  if case=='phase_negative':
   text=source.read_text(encoding='utf-8');assert text.count('.CLKC2_CPHASE(7)')==1
   candidate=folder/'sv_v3_memory_pll.v';candidate.write_text(text.replace('.CLKC2_CPHASE(7)','.CLKC2_CPHASE(6)'),encoding='utf-8')
  def invoke(name,args,required=True,label=None):
   with (folder/((label or name)+'.console.log')).open('w',encoding='utf-8') as f:
    p=subprocess.run([str(xb/(name+'.bat'))]+list(map(str,args)),cwd=folder,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=120)
   if required and p.returncode:raise RuntimeError(case+'/'+name+' failed; see console log')
   return p.returncode
  invoke('xvlog',['--log','compile.log',*model,candidate])
  invoke('xvlog',['--log','compile_tb.log',tb],label='xvlog_tb')
  invoke('xelab',['work.tb_v3_pll','-s','pll','--mt','off','--timescale','1ns/1ps','--log','elab.log'])
  rc=invoke('xsim',['pll','-runall','--log','sim.log'],False)
  text=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
  if case=='baseline':
   passed=rc==0 and 'PASS tb_v3_pll comparisons=301 errors=0' in text and '$finish called' in text and '[FAIL]' not in text
  else:
   passed='[FAIL] SDRAM50MHz rising edge +8ns from MEM' in text and 'Fatal: PLL clock/phase contract errors=' in text and 'PASS tb_v3_pll' not in text
  results.append({'case':case,'status':'PASS' if passed else 'FAIL','simulation_exit':rc})
 if any(hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p)] for p in files):raise RuntimeError('source changed during run')
 complete=all(r['status']=='PASS' for r in results)
 (base/'results.json').write_text(json.dumps({'results':results,'complete':complete,'hardware_verified':False,'models':'unchanged installed TD sim_release primitives'},indent=2),encoding='utf-8')
 print(json.dumps(results,indent=2));return 0 if complete else 1
if __name__=='__main__':sys.exit(main())
