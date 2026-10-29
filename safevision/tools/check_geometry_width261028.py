


from pathlib import Path
import argparse,hashlib,json,platform,time
import numpy as np

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def check(root):
 start=time.monotonic();source=root/'safevision/rtl/media/v3_bmp_normalizer.v';text=source.read_text('utf-8-sig')
 for anchor in ['localparam SB=FLEX_PIXELS?15:11,XB=FLEX_PIXELS?15:12;',
                'localparam GB=FLEX_PIXELS?SB+8:SB+XB;',
                'wire[GB-1:0] geometry_scratch={y_error,x_error};',
                "wire[15:0] abs_height=top_down?(~height+16'd1):height;",
                'if(width==0||width>(FLEX_PIXELS?16384:1920)||abs_height==0||abs_height>(FLEX_PIXELS?16384:1080))begin',
                'w<=width[SB-1:0];h<=abs_height[SB-1:0];',
                "wire[SB+1:0] saved_width3={1'b0,w,1'b0}+{2'b0,w};",
                "wire saved_shape_wide=saved_width3>={h,2'b0};",
                'if(initial_y)wide<=saved_shape_wide;else geometry_ge_q<=geometry_scratch>=geometry_divisor;',
                'geometry_ge_q<=geometry_scratch>=geometry_divisor;',
                "wire[SB+9:0] saved_width480=w*10'd480,saved_height640=h*10'd640;",
                '{y_error,x_error}<=wide?saved_height640:saved_width480;',
                'src_row<=wide?w:h;',
                "end else if(geometry_ge_q)begin {y_error,x_error}<=geometry_scratch-geometry_divisor;store_x<=store_x+1'b1;state<=GEOM;end",
                "else if(geometry_scratch>=geometry_divisor)begin {y_error,x_error}<=geometry_scratch-geometry_divisor;store_x<=store_x+1'b1;end"]:
  assert text.count(anchor)==1,anchor
 assert text.count('geometry_scratch-geometry_divisor')==2
 h=np.arange(1,16385,dtype=np.uint32)[None,:];pairs=0;maximum=0;maximum_quotient=0;digest=hashlib.sha256()

 raw_negative=np.uint32(65536)-h
 decoded_negative=(((~raw_negative)&np.uint32(65535))+np.uint32(1))&np.uint32(65535)
 assert np.array_equal(decoded_negative,h)
 assert np.all(h>0) and np.all(h<=16384)
 for first in range(1,16385,128):
  w=np.arange(first,min(first+128,16385),dtype=np.uint32)[:,None]
  wide=w*480>=h*640

  actual_wide=((((w<<1)+w)&np.uint32(131071))>=((h<<2)&np.uint32(131071)))
  assert np.array_equal(actual_wide,wide)
  numerator=np.where(actual_wide,h*640,w*480)
  assert np.array_equal(numerator,np.minimum(w*480,h*640))
  assert np.all(w*480<2**25) and np.all(h*640<2**25)
  divisor=np.where(wide,w,h)
  quotient=numerator//divisor;remainder=numerator%divisor

  assert np.all(divisor>0)
  assert np.all(numerator<=480*16384) and np.all(numerator<2**23)
  assert np.all(numerator==quotient*divisor+remainder)
  assert np.all(remainder<divisor)
  assert np.all(quotient<=640)
  assert np.array_equal(numerator&((1<<23)-1),numerator)

  first_remainder=np.where(quotient>0,numerator-divisor,numerator)
  last_before=np.where(quotient>0,remainder+divisor,numerator)
  assert np.all(first_remainder<=numerator)
  assert np.all(last_before<=numerator)
  assert np.all(last_before<2**23)
  digest.update(numerator.astype('<u4',copy=False).tobytes())
  digest.update(divisor.astype('<u4',copy=False).tobytes())
  pairs+=numerator.size;maximum=max(maximum,int(numerator.max()));maximum_quotient=max(maximum_quotient,int(quotient.max()))
 assert pairs==16384**2 and maximum==480*16384
 return dict(accepted=True,scope='Integer-domain invariant proof supplement; HDL and hardware qualification remain separate',dimension_pairs=pairs,width_range=[1,16384],height_range=[1,16384],height_representations=2,candidate_bits=23,original_scratch_bits=30,discarded_high_tuple_bits=7,full_numerator_bits=25,minimum_identity='N = min(480*W,640*H)',maximum_initial_numerator=maximum,maximum_quotient=maximum_quotient,subtraction_invariant='0 <= S-D <= S <= N <= 480*16384 < 2^23 whenever S >= D > 0',vectors_sha256=digest.hexdigest(),source_sha256=sha(source),tool_sha256=sha(Path(__file__)),python=platform.python_version(),numpy=np.__version__,elapsed_s=round(time.monotonic()-start,3))

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:result=check(a.repo.resolve())
 except Exception as error:result=dict(accepted=False,error=type(error).__name__+': '+str(error))
 a.output.write_text(json.dumps(result,indent=2)+'\n','utf-8');print('GEOMETRY WIDTH '+('PASS'if result['accepted']else'FAIL: '+result['error']));return 0 if result['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
