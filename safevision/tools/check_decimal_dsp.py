"""Bind the complete parser edit and prove its modulo24 arithmetic identity."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
PARENT='e796999e6309bb5d1d06f7b8b1f41af580251060'
SOURCE='safevision/rtl/control/v3_command_parser_catalog.v'
META='safevision/verification/models/decimal_dsp135.freeze.json'
MODEL='safevision/verification/models/v3_command_parser_decimal_frozen.sv'
ORIGINAL_SHA='2df89083cb8337b5c7886a1bf8220542ffd9ae2796b975caec1a396d4d94a4e3'
REFERENCE_SHA='6832cc44a5bd56e0af7258477deac7fa588a86ff0fa6fbcf0e990900948cabc4'
BEFORE=''' // Exact modulo24-bit decimal multiply-add. Carry-save compression leaves
 // one local ripple addition, avoiding two cascaded18-bit DSP multipliers.
 wire[23:0] decimal_a={number[20:0],3'b000};
 wire[23:0] decimal_b={number[22:0],1'b0};
 wire[23:0] decimal_c={20'd0,rx_data[3:0]};
 (* keep="true" *) wire[23:0] decimal_sum=decimal_a^decimal_b^decimal_c;
 (* keep="true" *) wire[23:0] decimal_carry=((decimal_a&decimal_b)|(decimal_a&decimal_c)|(decimal_b&decimal_c))<<1;
 (* keep="true",use_ripple=1 *) wire[23:0] decimal_next=decimal_sum+decimal_carry;'''
AFTER=''' // Exact modulo24-bit decimal multiply-add. Reuse the two DSP blocks
 // released by direct row lookup; no register or accepted-byte edge changes.
 (* use_dsp=1,dsp_style="yes" *) wire[27:0] decimal_product=number*4'd10;
 wire[23:0] decimal_next=decimal_product[23:0]+{20'd0,rx_data[3:0]};'''
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(root):
 old=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+SOURCE])
 if hashlib.sha256(old).hexdigest()!=ORIGINAL_SHA:raise ValueError('original complete parser changed')
 meta=json.loads((root/META).read_text('utf-8-sig'))
 expected=dict(parent_commit=PARENT,source=SOURCE,source_sha256=ORIGINAL_SHA,model=MODEL,model_sha256=REFERENCE_SHA,before=BEFORE,after=AFTER)
 if meta!=expected:raise ValueError('decimal transform metadata differs')
 frozen=old.replace(b'module v3_command_parser_catalog #(',b'module v3_command_parser_decimal_frozen #(')
 if(root/MODEL).read_bytes()!=frozen or sha(root/MODEL)!=REFERENCE_SHA:raise ValueError('reference differs beyond its module declaration')
 text=old.decode('utf-8-sig')
 if text.count(BEFORE)!=1 or(root/SOURCE).read_text('utf-8-sig')!=text.replace(BEFORE,AFTER):raise ValueError('unreviewed parser edit')
 # For each bit, parity + twice majority equals a+b+c. Summing these eight
 # one-bit identities proves carry-save addition modulo2**24 for all vectors.
 truth=[]
 for a in(0,1):
  for b in(0,1):
   for c in(0,1):
    left=(a^b^c)+2*((a&b)|(a&c)|(b&c));right=a+b+c
    if left!=right:raise ValueError('carry-save bit identity failed')
    truth.append([a,b,c,left,right])
 maximum=((1<<24)-1)*10
 if maximum>=(1<<28)or(1<<3)+(1<<1)!=10:raise ValueError('product width or coefficient proof failed')
 return dict(accepted=True,parent_commit=PARENT,source_sha256=sha(root/SOURCE),model_sha256=sha(root/MODEL),metadata_sha256=sha(root/META),tool_sha256=sha(Path(__file__)),scope='Whole parser binding and exact integer identity; native simulation and STA are separate',carry_save_bit_truth_table=truth,accumulator_bits=24,nibble_bits=4,domain_pairs=1<<28,maximum_full_product=maximum,product_bits=28,public_state_reset_and_latency_unchanged=True,added_latency_cycles=0,new_timing_exception=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('DECIMAL SOURCE/IDENTITY '+('PASS'if r['accepted']else'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
