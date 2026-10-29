
from pathlib import Path
import argparse,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
PARENT='a17618d3c56be0fc827c53fdbf808aef823a5a65'
BASELINE='09faac2e8fa718c9f92ef4a5013b68003ec8afe6'
ADC='safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_physical_base.adc'
ADC_SHA='fb8795f1c002371b8fc4fbab96f690cf34441f8ae02084ddadab0c90cd385c28'
TIMING_AND_PIN_SHA={'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_audio_pll.v': '4ec8202b045f058cf014017437e3167f6d4f7ae195ff4eb17f0227c385e6e891', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_v3_memory_pll.ipc': '8f22407866987c1d7a569de91c421fccc33429d2f98a1615dacc345193b74c70', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_v3_memory_pll.provenance.json': 'b2b25b874560bb50d2e527960ce96a47f99ca746b0b91e3cd94be4acca9cea40', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_v3_memory_pll.v': '188361d9f5a9ad7f6721e9dbd47cae2a0df0d97c74b12487eddd418a2feab219', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_hd_pll.v': '44e28474683a4c7ddd2777d709859603c30deda0c19842967707b234785960b1', 'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_vga_pll.v': '68e55f0a221d445703fb4104f6f08b6357b9f3370fb12ef1ef5c31df4ad50b62', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/io_budget.json': '32224f34c341aeaf6a3b5e7816eb875887d2fbf06e21e30693dcfac4ccfa0d3f', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/pll50_check.sdc': '7fb21aed0231a68f650954db59f7b60209b012eec256b4ad9602835e00f5f06e', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/pll50_check.tcl': 'b97b19f45ad7ed9e0bc44ced0d8ff1c3c280f03d9096a8de9a5db10603a53f1a', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board.adc': '4a068c3132512704ad09f8291e7b0875312fa10c70cc1960964a5388b923c766', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board.sdc': '9caa890b7115bbf4804365b76d08f6a391a5039039e0b38cf9e8bccd63298dd4', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_cdc.sdc': '074fde62b53fb4b5f238e7ceecfff447d1d5d46282398c946617e773687efc7a', 'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_cdc_audit.tcl': '3159d757cb389eb450f37fa4ef1fbae1100c8488cd2b2dec6b197a2d0a33fcc6', 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v': '0ace3c2d5da5ea15547a8f9c66a2f1bc28de31cb33b146ec750bd6771f6f69e9', 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/v3_mem_activity_tag.v': '7e9a26e289a315d0392c29a345864ac4d40da787d46921215d0a03a11b35e204', 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/v3_phy_reset_fanout.v': '548c31966f8bc87ab6a86c054ab5cc0cd84fcc56cc00f81d9455ab26d506493d', 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/v3_related_status_capture.v': '5074e13f0f1dfe9c5e55734102b03fda46efe74deb0d57646a2d379ccd068d7f', 'safevision/tools/configure_v3_pll.py': 'caf11ebf9a336350f7e333316f86d59ded549b41969d654eec60be82f3ed6bd6', 'safevision/tools/run_v3_pll.py': '8a5d50a5514e337aca004edefb293cb28382cf7b6626e3feb19a9bafde99bfa0'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check_source(root):
 raw=subprocess.check_output(['git','-C',str(root),'cat-file','blob',BASELINE+':'+ADC])
 if hashlib.sha256(raw).hexdigest()!=ADC_SHA or(root/ADC).read_bytes()!=raw:raise ValueError('automatic RAM mode is not the exact proven BASE OE-only placement file')
 for name,digest in TIMING_AND_PIN_SHA.items():
  if sha(root/name)!=digest:raise ValueError('board pin, clock, timing budget or CDC audit changed: '+name)
 from v3_sources import physical_constraint_files,required_media_bram_locations
 physical_constraint_files(root,'base')
 if required_media_bram_locations(root,'base')or required_media_bram_locations(root,'hd'):raise ValueError('automatic RAM mode contains fixed RAM positions')
 return dict(accepted=True,scope='Only internal RAM placement is automatic; exact proven BASE SDRAM-OE location and all parent board/clock/SDC/IO budgets remain frozen.',parent_commit=PARENT,baseline_commit=BASELINE,adc_sha256=ADC_SHA,unchanged_timing_and_pin_sha256=TIMING_AND_PIN_SHA,tool_sha256=sha(Path(__file__)),expected_fixed_ram_locations=0,board_pins_unchanged=True,timing_constraints_or_clocks_changed=False,hardware_verified=False)
def check_native(root,folder):
 source=check_source(root);record=json.loads((folder/'build.manifest.json').read_text('utf-8-sig'))
 from v3_sources import snapshot
 if record['status']!='PASS'or not record['source_unchanged']or not record['source_commit_binding']['verified']or record['sources']!=snapshot(root):raise ValueError('automatic-placement native source identity or strict PASS missing')
 gate=record['gate']
 if not gate['gate_accepted']or not gate['timing_passed']or gate['errors']or gate['sta']['negative_path_count']:raise ValueError('automatic-placement native timing rejected')
 path=folder/'route.bram.adc';sta=json.loads((folder/'final_sta.manifest.json').read_text('utf-8-sig'))
 if sha(path)!=sta['bram_location_report_sha256']:raise ValueError('actual native RAM readback changed')
 rows=[]
 for line in path.read_text('utf-8-sig').splitlines():
  if not line.strip():continue
  m=re.fullmatch(r'set_inst_assignment \{([^}]+)\} \{LOCATION = (X[0-9]+Y[0-9]+Z[0-9]+);\}',line)
  if not m:raise ValueError('invalid actual RAM placement row')
  rows.append(m.groups())
 expected=gate['resources']['bram']['used']+gate['resources']['bram32k']['used']
 if len(rows)!=expected or len(dict(rows))!=expected or len({loc for name,loc in rows})!=expected:raise ValueError('actual RAM inventory or location uniqueness differs')
 return dict(accepted=True,source=source,actual_native_ram_macros=len(rows),actual_locations=dict(rows),ram_readback_sha256=sha(path),strict_negative_path_count=0,bit_generated=False,hardware_verified=False)
def main():
 p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=ROOT);p.add_argument('--native',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 try:r=check_native(a.repo.resolve(),a.native.resolve())if a.native else check_source(a.repo.resolve())
 except Exception as exc:r=dict(accepted=False,error=str(exc))
 a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8');print('AUTO RAM PLACEMENT '+('PASS'if r['accepted']else'FAIL '+r['error']));return 0 if r['accepted']else 1
if __name__=='__main__':raise SystemExit(main())
