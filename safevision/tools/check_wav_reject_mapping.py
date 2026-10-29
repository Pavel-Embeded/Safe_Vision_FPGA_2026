"""Bind synthesis-only WAV rejection boundaries to the complete frozen parser."""
from pathlib import Path
import argparse,hashlib,json,subprocess

ROOT=Path(__file__).resolve().parents[2]
PARENT='5fdf4778f19a8a1ac8a29faf1030fc2ad77922cf'
SOURCE='safevision/rtl/media/v3_wav_parser_compact_ctx.v'
PARENT_SHA='d0896f4bf0b7fcc77096f4459d2e4d6fa45adeaf667d02274740f27b08ab53b6'
NAMES=('reject_header','reject_chunk_format','reject_format','reject_tail','reject_body_state')

def check_parser(root):
 raw=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+SOURCE])
 if hashlib.sha256(raw).hexdigest()!=PARENT_SHA:raise ValueError('frozen parser blob differs')
 expected=raw.decode('utf-8-sig')
 for name in NAMES:
  marker='wire '+name+'='
  if expected.count(marker)!=1:raise ValueError('frozen rejection class differs')
  expected=expected.replace(marker,'(* keep="true" *) '+marker)
 actual=(root/SOURCE).read_text('utf-8-sig')
 if actual!=expected:raise ValueError('change beyond the five synthesis attributes')
 return dict(accepted=True,parent_commit=PARENT,parent_parser_sha256=PARENT_SHA,source_sha256=hashlib.sha256((root/SOURCE).read_bytes()).hexdigest(),retained_classes=list(NAMES),verilog_operators_state_interface_and_mutation_anchors_unchanged=True,register_bits_added=0,latency_cycles_added=0,hardware_verified=False)

def check(root):
 result=check_parser(root)
 from check_auto_ram_placement import check_source
 clocks=check_source(root)
 if not clocks['accepted']or clocks['timing_constraints_or_clocks_changed']:raise ValueError('clock/pin profile differs')
 result.update(tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),clock_pin_source_proof=clocks,clock_reset_constraints_changed=False)
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n','utf-8');print('WAV REJECTION MAPPING '+('PASS'if r['accepted']else'FAIL '+r['error']))
 return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
