import argparse
import hashlib
import json
from pathlib import Path
import random
import re

ROOT=Path(__file__).resolve().parents[2]
FLOW=Path('safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify')
PHASE_SDC='set_multicycle_path -setup -from [get_cells {player/u_bmp/mult0*}] -to [get_regs {player/u_bmp/header_trunc_q}] 2\nset_multicycle_path -hold -from [get_cells {player/u_bmp/mult0*}] -to [get_regs {player/u_bmp/header_trunc_q}] 1\n'

def check(root=ROOT,constraints=True):
    path=root/'safevision/rtl/media/bmp_parser.v'
    text=re.sub(r'\s+','',path.read_text('utf-8-sig'))
    markers=(
        "wiredib_borrow0=offbits_r[7:0]<8'd14;",
        'wiredib_borrow1=dib_borrow0&&(offbits_r[15:8]==0);',
        'wiredib_borrow2=dib_borrow1&&(offbits_r[23:16]==0);',
        "wire[7:0]dib_cap0=offbits_r[7:0]-8'd14;",
        "wire[7:0]dib_cap1=offbits_r[15:8]-{7'd0,dib_borrow0};",
        "wire[7:0]dib_cap2=offbits_r[23:16]-{7'd0,dib_borrow1};",
        "wire[7:0]dib_cap3=offbits_r[31:24]-{7'd0,dib_borrow2};",
        "wire[32:0]checked_extent={1'b0,offbits_r}+{1'b0,required_bytes};",
        "wireheader_late=(mstate==H_HEAD)&&((hcnt==6'd52)||(hcnt==6'd53));",
        'if(!FLEX_PIXELS||header_late)header_trunc_q<=trunc_checked;',
    )
    for marker in markers:
        if text.count(marker)!=1:raise ValueError('BMP extent phase contract differs: '+marker)
    cases=0
    for position in range(4):
        for value in range(256):
            for borrow in ((14,)if position==0 else(0,1)):
                result=(value-borrow)&255
                carry=value<borrow
                if position and carry!=(borrow==1 and value==0):raise ValueError('byte borrow recurrence differs')
                if result!=(value-borrow)%256:raise ValueError('byte subtraction differs')
                cases+=1
    rng=random.Random(0x26102872)
    words=[0,1,13,14,15,54,255,256,65535,65536,0xffffffff]+[rng.getrandbits(32)for _ in range(4096)]
    for word in words:
        borrow=14;result=0
        for position in range(4):
            value=(word>>(position*8))&255
            result|=((value-borrow)&255)<<(position*8)
            borrow=int(value<borrow)
        if result!=(word-14)&0xffffffff:raise ValueError('composed BMP offset subtraction differs')
    if constraints:
        sdc=(root/FLOW/'v3_cdc.sdc').read_text('utf-8-sig').splitlines()
        for line in PHASE_SDC.splitlines():
            if sdc.count(line)!=1:raise ValueError('missing/duplicate paired header timing exception')
    return {'accepted':True,'byte_cases':cases,'word_cases':len(words),'capture_bytes':[52,53],'setup_cycles':2,'hold_cycles':1,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    result=check()
    if args.output:args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result))

if __name__=='__main__':main()
