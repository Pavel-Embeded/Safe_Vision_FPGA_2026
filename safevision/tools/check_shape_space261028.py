
from pathlib import Path
import argparse,hashlib,json,platform
import numpy as np
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(root):
 source=root/'safevision/rtl/media/v3_bmp_normalizer.v';text=source.read_text('utf-8-sig')
 assert "shape_width3={1'b0,width[SB-1:0],1'b0}+{2'b0,width[SB-1:0]}"in text
 assert "shape_wide=shape_width3>={abs_height[SB-1:0],2'b0}"in text
 assert "saved_width3={1'b0,w,1'b0}+{2'b0,w}"in text
 assert "saved_shape_wide=saved_width3>={h,2'b0}"in text
 assert "if(initial_y)wide<=saved_shape_wide"in text
 h=np.arange(1,16385,dtype=np.uint32)[None,:];digest=hashlib.sha256();compared=0

 assert np.all(((-((-h)&65535))&65535)==h)
 for first in range(1,16385,128):
  w=np.arange(first,min(first+128,16385),dtype=np.uint32)[:,None]
  original=w*480>=h*640
  actual=((((w<<1)+w)&131071)>=((h<<2)&131071))
  assert np.array_equal(original,actual),(first,'dimension decision differs')
  digest.update(np.packbits(actual,axis=None,bitorder='little').tobytes());compared+=actual.size
 assert compared==16384**2
 return dict(accepted=True,scope='Independent integer-domain replay, not a new HDL or board test',width_range=[1,16384],absolute_height_range=[1,16384],dimension_pairs=compared,height_representations=2,decision_matrix_sha256=digest.hexdigest(),source_sha256=sha(source),tool_sha256=sha(Path(__file__)),python=platform.python_version(),numpy=np.__version__)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as e:r=dict(accepted=False,error=type(e).__name__+': '+str(e))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('EXACT DIMENSION DOMAIN '+('PASS'if r['accepted']else'FAIL: '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
