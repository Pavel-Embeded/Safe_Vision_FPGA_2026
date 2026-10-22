"""Independent exhaustive integer proof for the HD3-cycle blend partition."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
def check(root):
 target=root/'safevision/rtl/hd/alpha_blend.v';raw=target.read_bytes();s=raw.decode('utf-8')
 # Tie the proof to the exact intended HDL operators, then compare with an
 # independent integer division oracle, including every carry boundary.
 required=("wire[13:0] sr_next=pr+14'd8287,sb_next=pb+14'd8287;",
 "wire[14:0] sg_next=pg+15'd16447;",
 "br2<=br+sr_next[12:8];bg2<=bg+sg_next[13:8];bb2<=bb+sb_next[12:8];",
 "cr<=sr_next[7:0]>=~{2'b0,sr_next[13:8]};",
 "cg<=sg_next[7:0]>=~{1'b0,sg_next[14:8]};",
 "cb<=sb_next[7:0]>=~{2'b0,sb_next[13:8]};",
 "wire[4:0] rr=br2+cr,rb=bb2+cb;wire[5:0] rg=bg2+cg;")
 for line in required:
  if s.count(line)!=1:raise ValueError('HDL arithmetic changed; reproving required:'+line)
 cases=[];total=0
 for numerator_bits,channel_bits in ((14,5),(15,6)):
  mask=(1<<channel_bits)-1;count=0
  for x in range(1<<numerator_bits):
   high,low=x>>8,x&255;carry=int(low>=255-high)
   for back in range(1<<channel_bits):
    base=(back+(high&mask))&mask;actual=(base+carry)&mask;expected=(back+x//255)&mask
    if actual!=expected:raise ValueError((x,back,actual,expected))
    count+=1
  cases.append(dict(numerator_bits=numerator_bits,channel_bits=channel_bits,comparisons=count));total+=count
 return dict(accepted=True,comparisons=total,cases=cases,rtl_sha256=hashlib.sha256(raw).hexdigest(),scope='Exact quotient/base/carry arithmetic; real cycle latency/reset/complete pixel equivalence separately tested',visible_latency=3)
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--output',type=Path);a=ap.parse_args();j=check(a.repo.resolve());text=json.dumps(j,indent=2)+'\n'
 if a.output:a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_bytes(text.encode())
 print(text,end='')
if __name__=='__main__':main()
