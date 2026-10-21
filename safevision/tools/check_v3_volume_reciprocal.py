"""Exhaust exact /100 over the superset of legal absolute PCM24*gain values."""
import argparse,hashlib,json,time
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 if a.output.exists():raise ValueError('use a fresh evidence path')
 rtl=ROOT/'safevision/rtl/audio/v3_audio_volume.v';text=rtl.read_text(encoding='utf-8')
 if "wire[61:0] reciprocal_product=product*32'h51eb851f;" not in text or 'reciprocal_product[60:37]' not in text:
  raise ValueError('this proof is bound to the reviewed absolute-product implementation')
 maximum=(1<<23)*100;magic=0x51eb851f;started=time.monotonic();count=0;errors=0
 for first in range(0,maximum+1,1<<22):
  stop=min(first+(1<<22),maximum+1);n=np.arange(first,stop,dtype=np.uint64)
  got=(n*np.uint64(magic))>>np.uint64(37);expected=n//np.uint64(100)
  errors+=int(np.count_nonzero(got!=expected));count+=stop-first
 if errors or count!=838860801:raise AssertionError('exhaustive reciprocal mismatch')
 result=dict(schema=1,complete=True,range_min=0,range_max=maximum,integer_values_compared=count,errors=0,
  magic=magic,shift=37,rounding_excess=100*magic-(1<<37),numpy_version=np.__version__,
  elapsed_s=round(time.monotonic()-started,3),rtl_sha256=hashlib.sha256(rtl.read_bytes()).hexdigest(),
  proof_script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
  scope='All possible absolute products; signed conversion and every public pin/edge are independently native simulated. No hardware/STA claim.')
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes((json.dumps(result,indent=2)+'\n').encode())
 print('PASS exact reciprocal values='+str(count)+' errors=0')
if __name__=='__main__':main()
