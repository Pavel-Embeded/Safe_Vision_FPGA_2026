
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
PARENT='f79d7525a51cd1e80912cb3c95f3d97b8560bb49'
SOURCE='safevision/rtl/audio/v3_audio_system.v'
PARENT_SHA='67fd39c4f1de83360f0173c6ec0e1486381e05b6a7d8f1f5e994db637b23c3fe'
PATCHES=[('PREINDEXED=0,DIRECT_RING_COMPARE=0)(', 'PREINDEXED=0,DIRECT_RING_COMPARE=0,PREFILL_PIPELINE=DIRECT_RING_COMPARE)('), (' wire [3:0] room,fill;wire', ' wire [3:0] room,fill,admission_fill;wire'), (' end endgenerate\n\n v3_wav_source', ' end endgenerate\n // The admission predicate is one REF cycle old in production. The source\n // services only one sector at a time; sector_room remains a CURRENT-cycle\n // hard capacity check at Q_CHOOSE. No PCM data, tag or handshake is delayed.\n generate if(PREFILL_PIPELINE)begin:registered_prefill\n  (* preserve="true",keep="true" *) reg[3:0] value;\n  always @(posedge ref_clk or negedge ref_rst_n)\n   if(!ref_rst_n)value<=0;else value<=fill;\n  assign admission_fill=value;\n end else begin:direct_prefill\n  assign admission_fill=fill;\n end endgenerate\n\n v3_wav_source'), ('.slot_fill(fill),.sector_room(room)', '.slot_fill(admission_fill),.sector_room(room)')]
def transform(text):
 for before,after in PATCHES:
  if text.count(before)!=1:raise ValueError('prefill transformation anchor differs')
  text=text.replace(before,after)
 return text
def check(root):
 raw=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+SOURCE])
 if hashlib.sha256(raw).hexdigest()!=PARENT_SHA:raise ValueError('frozen audio assembly changed')
 if (root/SOURCE).read_text('utf-8-sig')!=transform(raw.decode('utf-8-sig')):raise ValueError('audio source changed beyond admission register')


 return dict(accepted=True,parent_commit=PARENT,parent_source_sha256=PARENT_SHA,source_sha256=hashlib.sha256((root/SOURCE).read_bytes()).hexdigest(),tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),scope='Exact complete-body transformation; one REF cycle of admission lookahead only. Native PCM, admission/reset tests and strict routed STA are separate.',admission_delay_ref_cycles=1,added_state_bits=4,current_sector_room_retained=True,pcm_data_tag_handshake_unchanged=True,global_and_media_reset_epochs_unchanged=True,library_default_bypass=True,production_selected_by='PREFILL_PIPELINE defaults to DIRECT_RING_COMPARE',clock_or_timing_constraints_changed=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('PREFILL ADMISSION SOURCE '+('PASS'if r['accepted']else 'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
