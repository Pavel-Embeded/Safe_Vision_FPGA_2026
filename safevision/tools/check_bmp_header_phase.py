"""Bind the complete parser transform and prove its bytewise subtraction."""
import argparse,hashlib,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE='safevision/rtl/media/bmp_parser.v'
MODEL='safevision/verification/models/bmp_parser_frozen_extent.sv'
META='safevision/verification/models/bmp_parser_frozen_extent.freeze.json'
PARENT='2204949e4a4257fbbda48988ffd84a3db37ba181'
ORIGINAL_SHA='612fc193dbb9aecde2ffa6e03e9d09dae5a0a8b0d6d5bc2b660721b62d0f56d2'
DIB_BEFORE='    wire [31:0] dib_capacity = offbits_delta;'
DIB_AFTER="""    // Exact unsigned32-bit subtraction by14, with a bounded byte path.
    // The borrow prefix contains only zero-byte tests; no parser-state mux
    // or full32-bit arithmetic feeds the byte14..17 DIB comparisons.
    wire dib_borrow0=offbits_r[7:0]<8'd14;
    wire dib_borrow1=dib_borrow0&&(offbits_r[15:8]==0);
    wire dib_borrow2=dib_borrow1&&(offbits_r[23:16]==0);
    wire[7:0] dib_cap0=offbits_r[7:0]-8'd14;
    wire[7:0] dib_cap1=offbits_r[15:8]-{7'd0,dib_borrow0};
    wire[7:0] dib_cap2=offbits_r[23:16]-{7'd0,dib_borrow1};
    wire[7:0] dib_cap3=offbits_r[31:24]-{7'd0,dib_borrow2};
    wire [31:0] dib_capacity = FLEX_PIXELS?{dib_cap3,dib_cap2,dib_cap1,dib_cap0}:offbits_delta;"""
PHASE_BEFORE='    reg[4:0] header_predicates_q;\n    always @(posedge clk) header_predicates_q<={sig_ok,dib_ok,size_ok,fmt_ok,trunc_ok};'
PHASE_AFTER='    // Capture the extent predicate only in the last two header positions.\n    // hcnt advances only on accepted bytes. Size operands finish by byte33,\n    // leaving at least19accepted clocks before the first possible capture.\n    // Byte53 publication and all continuous legacy outputs are unchanged.\n    wire[32:0] checked_extent={1\'b0,offbits_r}+{1\'b0,required_bytes};\n    wire trunc_checked=(offbits_r>=BMP_HDR_BYTES)&&(bfsize_r<=file_size)&&\n                       (checked_extent<={1\'b0,(VARIABLE_SIZE?bfsize_r:file_size)});\n    wire header_late=(mstate==H_HEAD)&&((hcnt==6\'d52)||(hcnt==6\'d53));\n    reg[4:1] header_predicates_q;\n    (* keep="true" *) reg header_trunc_q;\n    always @(posedge clk)begin\n      header_predicates_q<={sig_ok,dib_ok,size_ok,fmt_ok};\n      if(!FLEX_PIXELS||header_late)header_trunc_q<=trunc_checked;\n    end'
FINAL_BEFORE='wire final_trunc=FLEX_PIXELS?header_predicates_q[0]:trunc_ok;'
FINAL_AFTER='wire final_trunc=FLEX_PIXELS?header_trunc_q:trunc_ok;'

PHASE_SDC='# Header extent: product is stable at least19 clocks before byte52 capture.\n# Restrict the exception to this DSP and this private predicate; paired hold\n# restores the ordinary minimum-delay edge. All other paths stay single-cycle.\nset_multicycle_path -setup -from [get_cells {player/u_bmp/mult0*}] -to [get_regs {player/u_bmp/header_trunc_q}] 2\nset_multicycle_path -hold -from [get_cells {player/u_bmp/mult0*}] -to [get_regs {player/u_bmp/header_trunc_q}] 1\n'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def check(root, constraints=True):
 meta=json.loads((root/META).read_text('utf-8-sig'))
 if(meta['parent_commit'],meta['source_path'],meta['reference_path'],meta['rename_from'],meta['rename_to'])!=(PARENT,SOURCE,MODEL,'module bmp_parser #(','module bmp_parser_frozen_extent #('):raise ValueError('frozen parser identity differs')
 old=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+SOURCE])
 if hashlib.sha256(old).hexdigest()!=ORIGINAL_SHA or meta['source_sha256']!=ORIGINAL_SHA:raise ValueError('original parser bytes differ')
 frozen=old.replace(meta['rename_from'].encode(),meta['rename_to'].encode())
 if old.count(meta['rename_from'].encode())!=1 or(root/MODEL).read_bytes()!=frozen or sha(root/MODEL)!=meta['reference_sha256']:raise ValueError('reference changed beyond its module declaration')
 expected=old.decode('utf-8-sig')
 for before,after in ((DIB_BEFORE,DIB_AFTER),(PHASE_BEFORE,PHASE_AFTER),(FINAL_BEFORE,FINAL_AFTER)):
  if expected.count(before)!=1:raise ValueError('parser transform anchor differs')
  expected=expected.replace(before,after)
 if(root/SOURCE).read_text('utf-8-sig')!=expected:raise ValueError('parser changed beyond the reviewed private arithmetic transform')
 # All13weak orderings of bfSize, file_size and the33-bit extent cover
 # the comparison identity. Overflow is an extent greater than BOTH32-bit
 # limits and therefore cannot be accepted after the simplification.
 orders=set()
 for bf in range(3):
  for file_size in range(3):
   for end in range(3):
    orders.add(((bf>file_size)-(bf<file_size),(end>file_size)-(end<file_size),(end>bf)-(end<bf)))
    for variable in(0,1):
     old=(bf<=file_size)and(end<=file_size)and(not variable or end<=bf)
     new=(bf<=file_size)and(end<=(bf if variable else file_size))
     if old!=new:raise ValueError('extent transitivity differs')
 if len(orders)!=13:raise ValueError('comparison order coverage differs')
 for bf,file_size,end in ((0xffffffff,0xffffffff,0x100000000),(0,0xffffffff,0x100000000),(0xffffffff,0xffffffff,0x1fffffffe)):
  for variable in(0,1):
   if (bf<=file_size and end<=(bf if variable else file_size)):raise ValueError('33-bit overflow accepted')
 # First byte subtracts14. Every higher byte subtracts only the incoming
 # borrow; the outgoing borrow is exactly (byte==0 && incoming_borrow).
 # These complete256+3*512byte cases prove all2^32words by composition.
 recurrence=0;digest=hashlib.sha256()
 for byte in range(256):
  result=(byte-14)&255;borrow=byte<14
  if byte-14!=result-256*int(borrow):raise ValueError('low-byte identity differs')
  recurrence+=1;digest.update(bytes((byte,result,int(borrow))))
 for position in range(1,4):
  for byte in range(256):
   for incoming in (0,1):
    result=(byte-incoming)&255;borrow=bool(incoming and byte==0)
    if byte-incoming!=result-256*int(borrow):raise ValueError('byte borrow recurrence differs')
    recurrence+=1;digest.update(bytes((position,byte,incoming,result,int(borrow))))
 values={0,1,13,14,15,53,54,55,255,256,257,65535,65536,65549,16777215,16777216,0xfffffff0,0xffffffff}
 rng=random.Random(0x26102872);values.update(rng.getrandbits(32)for _ in range(32768))
 for n in sorted(values):
  b=[(n>>(8*i))&255 for i in range(4)];q=[(b[0]-14)&255];borrow=b[0]<14
  for i in range(1,4):q.append((b[i]-int(borrow))&255);borrow=borrow and b[i]==0
  actual=sum(v<<(8*i)for i,v in enumerate(q))
  if actual!=((n-14)&0xffffffff):raise ValueError('composed word differs')
  digest.update(n.to_bytes(4,'little')+actual.to_bytes(4,'little'))
 # Complete-source equality above pins all state transitions and field writes.
 # The accepted byte counter starts at0, advances by1 only on valid&&ready,
 # and cannot jump to52. Pixel-format operands finish no later than byte29;
 # the two product stages settle conservatively by33. Captures52/53 leave
 # at least19 cycles of stable product, even at one accepted byte per cycle.
 for capture in (52,53):
  for stall in (0,1,2,17,10000):
   if capture-33+stall<2:raise ValueError('insufficient product settle window')
 if constraints:
  flow='safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/'
  original=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+flow+'v3_cdc.sdc'])
  expected_sdc=original+PHASE_SDC.encode('ascii')
  if(root/flow/'v3_cdc.sdc').read_bytes()!=expected_sdc:raise ValueError('constraints changed beyond exact phase exception')
  if(root/flow/'v3_board.sdc').read_bytes()!=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+flow+'v3_board.sdc']):raise ValueError('board clock/IO constraints changed')
 return dict(accepted=True,scope='Complete source transform, full-word unsigned subtraction induction and late-header stable-data contract; separate native simulation and routed timing required',
             bound_weak_order_classes=len(orders),bound_transitivity_proven=True,dib_word_domain=2**32,exhaustive_byte_recurrence_cases=recurrence,independent_word_spot_checks=len(values),decision_sha256=digest.hexdigest(),
             source_sha256=sha(root/SOURCE),model_sha256=sha(root/MODEL),metadata_sha256=sha(root/META),tool_sha256=sha(Path(__file__)),
             legacy_flex0_combinational_behavior_preserved=True,all_other_parser_state_and_outputs_unchanged=True,
             extent_sum_bits=33,private_sum_stages=0,late_capture_bytes=[52,53],setup_cycles=2,hold_cycles=1,minimum_stable_cycles=19,header_publication_byte=53,conservative_latest_settle_byte=33,
             operands='bfOffBits completes atbyte13; all size/format operands complete bybyte33; one-byte/clock leaves16clocks beforebyte53',
             constraints_changed=bool(constraints),multicycle_scope="one DSP to one exact header predicate register",hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=type(exc).__name__+': '+str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('BMP HEADER TRANSFORM '+('PASS'if r['accepted']else'FAILED '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
