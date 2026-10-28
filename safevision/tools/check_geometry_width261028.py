"""Exhaust legal geometry inputs and justify the reduced temporary width.

This is integer-domain evidence in addition to native HDL pixel/FSM tests.
For N>=0,D>0, every executed subtraction has S>=D and produces S-D>=0.
Thus no intermediate remainder exceeds N. Checking the initial numerator bound
over all dimensions proves that dropping the unreachable upper five bits is
exact throughout the subtractive quotient loop.
"""
from pathlib import Path
import argparse,hashlib,json,platform,time
import numpy as np

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def check(root):
 start=time.monotonic();source=root/'safevision/rtl/media/v3_bmp_normalizer.v';text=source.read_text('utf-8-sig')
 for anchor in ['localparam GB=FLEX_PIXELS?SB+10:SB+XB;',
                'wire[GB-1:0] geometry_scratch={y_error,x_error};',
                'geometry_ge_q<=geometry_scratch>=geometry_divisor;',
                '{y_error,x_error}<=wide?saved_height640:saved_width480;',
                'src_row<=wide?w:h;']:
  assert text.count(anchor)==1,anchor
 assert text.count('geometry_scratch-geometry_divisor')==2
 h=np.arange(1,16385,dtype=np.uint32)[None,:];pairs=0;maximum=0;maximum_quotient=0;digest=hashlib.sha256()
 for first in range(1,16385,128):
  w=np.arange(first,min(first+128,16385),dtype=np.uint32)[:,None]
  wide=w*480>=h*640
  numerator=np.where(wide,h*640,w*480)
  divisor=np.where(wide,w,h)
  quotient=numerator//divisor;remainder=numerator%divisor
  # These host formulas do not truncate to the candidate width.
  assert np.all(divisor>0)
  assert np.all(numerator<2**25)
  assert np.all(numerator==quotient*divisor+remainder)
  assert np.all(remainder<divisor)
  assert np.all(quotient<=640)
  assert np.array_equal(numerator&((1<<25)-1),numerator)
  # First and terminal executed subtractions bound every monotone remainder.
  first_remainder=np.where(quotient>0,numerator-divisor,numerator)
  last_before=np.where(quotient>0,remainder+divisor,numerator)
  assert np.all(first_remainder<=numerator)
  assert np.all(last_before<=numerator)
  assert np.all(last_before<2**25)
  digest.update(numerator.astype('<u4',copy=False).tobytes())
  digest.update(divisor.astype('<u4',copy=False).tobytes())
  pairs+=numerator.size;maximum=max(maximum,int(numerator.max()));maximum_quotient=max(maximum_quotient,int(quotient.max()))
 assert pairs==16384**2
 return dict(accepted=True,scope='Integer-domain invariant proof supplement; HDL and hardware qualification remain separate',dimension_pairs=pairs,width_range=[1,16384],height_range=[1,16384],candidate_bits=25,original_scratch_bits=30,maximum_initial_numerator=maximum,maximum_quotient=maximum_quotient,subtraction_invariant='0 <= S-D <= S <= N < 2^25 whenever S >= D > 0',vectors_sha256=digest.hexdigest(),source_sha256=sha(source),tool_sha256=sha(Path(__file__)),python=platform.python_version(),numpy=np.__version__,elapsed_s=round(time.monotonic()-start,3))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:result=check(a.repo.resolve())
 except Exception as error:result=dict(accepted=False,error=type(error).__name__+': '+str(error))
 a.output.write_text(json.dumps(result,indent=2)+'\n','utf-8');print('GEOMETRY WIDTH '+('PASS'if result['accepted']else'FAIL: '+result['error']));return 0 if result['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
