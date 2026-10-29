"""Exhaust the complete24-bit accumulator and4-bit digit domain."""
from pathlib import Path
import argparse,hashlib,json,time
from check_decimal_dsp import check,ROOT
def run(root):
 import numpy as np
 bound=check(root);start=time.monotonic();mask=np.uint32(0xffffff);cases=0;bad9=0;bad_digit=0
 for begin in range(0,1<<24,1<<18):
  n=np.arange(begin,begin+(1<<18),dtype=np.uint32);a=(n<<3)&mask;b=(n<<1)&mask
  for digit in range(16):
   c=np.uint32(digit);s=a^b^c;carry=(((a&b)|(a&c)|(b&c))<<1)&mask
   old=(s+carry)&mask;new=(n*np.uint32(10)+c)&mask
   if not np.array_equal(old,new):raise ValueError('decimal mismatch at block/digit '+str((begin,digit)))
   bad9+=int(np.count_nonzero(old!=((n*np.uint32(9)+c)&mask)))
   bad_digit+=int(np.count_nonzero(old!=((n*np.uint32(10))&mask)));cases+=len(n)
 if cases!=1<<28 or bad9!=268435440 or bad_digit!=251658240:raise ValueError('incomplete domain/control coverage')
 return dict(accepted=True,scope='Exhaustive pure arithmetic comparison; FPGA DSP behavior is checked by native build and board tests',binding=bound,comparisons=cases,mismatches=0,times9_disagreements=bad9,missing_nibble_disagreements=bad_digit,numpy_version=np.__version__,elapsed_s=round(time.monotonic()-start,3),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=run(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('DECIMAL FULL DOMAIN '+('PASS'if r['accepted']else'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
