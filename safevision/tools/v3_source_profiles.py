"""Exact ordered BASE/HD implementation selection and native acknowledgement."""
from pathlib import Path
import re,hashlib
CANONICAL=(
 'platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v','rtl/control/media_recovery_ctrl.v','rtl/video/v3_status_layers.v',
 'rtl/video/v3_packed_row_store.v','rtl/video/v3_line_cache.v',
 'rtl/control/v3_uart_link.v','rtl/control/v3_supervisor.v',
 'rtl/video/v3_video_display_core.v','rtl/memory/v3_row_integrity.v','rtl/video/video_compositor/alpha_blend.v','rtl/control/v3_command_parser_catalog.v','rtl/audio/hdmi_acr.v','rtl/common/sv_async_fifo.v')
MAPPING={name:'rtl/hd/'+Path(name).name for name in CANONICAL}
MAPPING['rtl/common/sv_async_fifo.v']='platform/anlogic_eg4s20_hx4s20c/rtl/memory/sv_async_fifo_hd_phase.v'
def lines(path):
 return [r.strip()for r in path.read_text(encoding='utf-8-sig').splitlines()if r.strip()and not r.lstrip().startswith('#')]
def source_list(root,flow,mode):
 if mode not in ('base','hd'):raise ValueError('invalid source profile')
 common=root/flow/'v3_board_sources.list';hd=root/flow/'v3_board_sources_hd.list'
 if not hd.exists():
  if any((root/'safevision'/v).exists()for v in MAPPING.values()):raise ValueError('HD implementations exist but explicit HD manifest is missing')
  return common
 base=lines(common);selected=lines(hd)
 if len(base)!=len(set(base))or len(selected)!=len(set(selected)):raise ValueError('duplicate profile source')
 if any(base.count(n)!=1 for n in CANONICAL):raise ValueError('canonical profile substitution is missing/ambiguous')
 if selected!=[MAPPING.get(n,n)for n in base]:raise ValueError('HD list must contain exactly the ordered interface-compatible substitutions')
 for old,new in MAPPING.items():
  a=root/'safevision'/old;b=root/'safevision'/new
  if not a.is_file()or not b.is_file():raise ValueError('missing implementation')
  names=lambda p:re.findall(r'^\s*module\s+([A-Za-z_][A-Za-z_0-9]*)\b',p.read_text(encoding='utf-8'),re.M)
  if not names(a)or names(a)!=names(b):raise ValueError('HD implementation module names differ: '+old)
 return hd if mode=='hd'else common
def native_acknowledgement(root,folder,mode):
 from v3_sources import sources
 log=folder.parent/(mode+'.console.log')
 if(folder/'checkpoint.synthesis.json').is_file():
  # The implementation process imports gate.db and never invokes read_hdl.
  # Use its exact, checksum-linked synthesis process; reject a forged handoff.
  from v3_checkpoint_flow import verify_receipt
  verify_receipt(folder)
  log=folder/'synthesis.console.log'
 text=log.read_text(encoding='utf-8',errors='replace')
 matches=re.findall(r'^RUN-1002 : start command "read_hdl -file (.*?) -include_dir [^\r\n]*? -top safevision_v3_top"$',text,re.M)
 if len(matches)!=1:raise ValueError('missing/ambiguous actual native read_hdl command')
 actual=[str(Path(p).resolve()).casefold()for p in matches[0].split()]
 expected=[str((root/p).resolve()).casefold()for p in sources(root,mode)]
 if actual!=expected:raise ValueError('native ordered HDL inputs differ from GUI/shared source profile')
 return dict(accepted=True,mode=mode,ordered_hdl_count=len(actual),native_log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
