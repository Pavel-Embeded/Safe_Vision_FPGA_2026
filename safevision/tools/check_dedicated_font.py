"""Bind a dedicated full32glyph implementation without rebasing pixel gold."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
PARENT='5444950eb958684d0f79afa51cbd308e904ecaaa'
TOP='safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v'
TOP_SHA='41f14b76382af3bc1c16f0aa7f4ef43776e96dc28ccbfe327f901780a60415ea'
BENCH='safevision/verification/unit/tb_v3_ticker_board.sv'
BENCH_SHA='5a5e730e699f1f04c942f2483409f6180f759c22014a0e89b58071a05fa44129'
PATCHES=[('.SHARED_TICKER(TICKER_ENABLE),.SHARED_PACKED_FONT(TICKER_ENABLE)', '.SHARED_TICKER(0),.SHARED_PACKED_FONT(0)'), ('.EXTERNAL_FONT(1),.PACKED_EXTERNAL(1),.MESSAGE_CHARS(32)', '.EXTERNAL_FONT(0),.PACKED_EXTERNAL(0),.MESSAGE_CHARS(32)')]
BENCH_PATCHES=[('dut.scrolling.ticker.MESSAGE_CHARS==32&&dut.scrolling.ticker.EXTERNAL_FONT==1&&dut.scrolling.ticker.PACKED_EXTERNAL==1,"production selects all32losslessly shared glyphs"', 'dut.scrolling.ticker.MESSAGE_CHARS==32&&dut.scrolling.ticker.EXTERNAL_FONT==0&&dut.scrolling.ticker.PACKED_EXTERNAL==0,"production selects all32unchanged glyphs in dedicated one-bit RAM"'), ('dut.video.SHARED_TICKER==1&&dut.video.SHARED_PACKED_FONT==1,"production selects the checked9-bit shared memory layout"', 'dut.video.SHARED_TICKER==0&&dut.video.SHARED_PACKED_FONT==0,"production selects dedicated font and independent spectrum ports"')]
INVARIANT_SHA={'safevision/rtl/video/v3_scrolling_ticker.v': 'c31ab02e55a148c3994cf5fe9fc00c14fc67134f51fbacbd78321dcc0826d736', 'safevision/rtl/video/v3_audio_spectrum.v': 'c36487c5f4dee5980212482a2d01ff77fd9364b595e066ce290341001b048375', 'safevision/rtl/video/v3_video_display_core.v': '0638514c104865861f4602b524f13b62cdc3c411ed181d934b92e920216e9e04', 'safevision/rtl/hd/v3_video_display_core.v': '6848ee0e745f76e5af227f622e19c7166b76fd8b3691b7d494bf0ebbf583441b', 'safevision/assets/fonts/v3_ticker16.mem': 'db9b32e51a3ef8cdf735018c5ec3fa80698970b509312903556ecbc0a094eccf', 'safevision/assets/fonts/v3_ticker16.provenance.json': '2f3ffb988c3542d65c788352e56cfcad727070a66b5971b7cfa1db505443b756', 'safevision/assets/audio/v3_spectrum_twiddle.mem': '66e620e6e6b9f24486b06d350280fe225e639593e186212cfdccc3bb1b6c384a'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def transform(text,patches=PATCHES):
 for before,after in patches:
  if text.count(before)!=1:raise ValueError('dedicated font transformation anchor differs')
  text=text.replace(before,after)
 return text
def parent_top(root):
 b=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+TOP])
 if hashlib.sha256(b).hexdigest()!=TOP_SHA:raise ValueError('frozen TOP differs')
 return b.decode('utf-8-sig')
def check(root):
 prior=parent_top(root)
 if(root/TOP).read_text('utf-8-sig')!=transform(prior):raise ValueError('TOP changed beyond four font implementation parameters')
 bench=subprocess.check_output(['git','-C',str(root),'cat-file','blob',PARENT+':'+BENCH])
 if hashlib.sha256(bench).hexdigest()!=BENCH_SHA or(root/BENCH).read_text('utf-8-sig')!=transform(bench.decode('utf-8-sig'),BENCH_PATCHES):raise ValueError('pixel reference/stimulus changed beyond two explicit implementation-selection assertions')
 for name,digest in INVARIANT_SHA.items():
  if sha(root/name)!=digest:raise ValueError('renderer,video,FFT body or original full font changed: '+name)
 values=(root/'safevision/assets/fonts/v3_ticker16.mem').read_text('ascii').split()
 if len(values)!=8192 or any(v not in('0','1')for v in values):raise ValueError('full one-bit font shape differs')
 return dict(accepted=True,parent_commit=PARENT,parent_top_sha256=TOP_SHA,source_sha256=sha(root/TOP),bench_sha256=sha(root/BENCH),parent_bench_sha256=BENCH_SHA,unchanged_sha256=INVARIANT_SHA,tool_sha256=sha(Path(__file__)),scope='Complete TOP changes only four font implementation parameters; entire board stimulus and independent pixel gold unchanged, except two declared profile expectations. All renderer/FFT/video bodies and every original bitmap bit remain frozen.',message_characters=32,font_bits=8192,video_latency_clocks=21,source_ahead_pixels=5,added_video_latency=0,scroll_period_pixels=1024,clock_reset_or_constraints_changed=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('DEDICATED FULL FONT '+('PASS'if r['accepted']else'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
