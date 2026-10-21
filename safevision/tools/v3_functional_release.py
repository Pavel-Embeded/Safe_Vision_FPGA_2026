"""Bind release simulation acceptance and its complete inputs to the source commit."""
import hashlib,json
from pathlib import Path
from audit_v3_resource_checkpoint import audit,within

DEFAULT_MANIFEST=Path('evidence/v3/resource_113_20261016/acceptance.json')

def acceptance(root,manifest=DEFAULT_MANIFEST):
 if not __debug__:raise RuntimeError('functional release audit requires Python assertions enabled')
 root=root.resolve();manifest=within(root,manifest)
 result=audit(root,manifest)
 if not result['accepted']:raise ValueError('functional acceptance rejected')
 index=json.loads(manifest.read_text(encoding='utf-8'))
 files={manifest,root/'evidence/v3/current_100_20261016/selected_acceptance.json'}
 if (root/'safevision/rtl/hd/sdram_app_adapter.v').exists():files.add(root/'safevision/verification/models/hd_read64_stimulus.freeze.json')
 if 'dsp_style="yes"' in (root/'safevision/rtl/audio/v3_audio_volume.v').read_text(encoding='utf-8'):
  files.update({root/'evidence/v3/handbook_26101801/volume_math/exhaustive.json',root/'safevision/tools/check_v3_volume_reciprocal.py',root/'safevision/verification/models/v3_audio_volume_reference.freeze.json'})
 for model in ('v3_file_streamer_compact_reference','v3_controls_pipeline_reference','v3_uart_formatter_reference','v3_uart_tx_reference','v3_audio_root_reference','v3_recovery_reset_reference','v3_wav_reset_reference','v3_player_owner_reference','v3_pcm_ring_reference','v3_cluster_walker_reference','v3_wav_bounds_reference','hd_acr_reference','v3_led_publication_reference'):
  files.add(root/('safevision/verification/models/'+model+'.freeze.json'))
 if (root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board_sources_hd.list').exists():
  files.update(root/name for name in ['safevision/verification/models/v3_hd_alpha_reference.freeze.json', 'safevision/verification/models/v3_hd_guard_reference.freeze.json', 'safevision/verification/models/v3_hd_status_reference.freeze.json', 'safevision/verification/models/v3_hd_recovery_reference.freeze.json', 'safevision/verification/models/v3_hd_supervisor_reference.freeze.json', 'safevision/verification/models/tb_v3_hd_uart_formatter_equivalence.freeze.json', 'safevision/verification/models/tb_v3_hd_uart_link.freeze.json', 'safevision/verification/models/tb_v3_hd_uart_link_catalog.freeze.json', 'safevision/verification/models/tb_v3_hd_packed_rows.freeze.json', 'safevision/verification/models/tb_v3_hd_handbook_board.freeze.json', 'safevision/verification/models/tb_v3_hd_video_final.freeze.json', 'safevision/verification/models/tb_v3_hd_handbook_video.freeze.json'])
 if (root/'safevision/rtl/hd/alpha_blend.v').exists():
  files.update({root/'safevision/tools/check_v3_hd_alpha_math.py',root/'evidence/v3/handbook_26101901/alpha_math/exhaustive.json'})
 for row in index['positive_tests']+index['negative_controls']:
  folder=within(root,row['evidence'])
  # Curated case folders contain only provenance, raw logs, exact mutant bytes
  # and generated vectors. Include every file so none can drift after approval.
  files.update(p for p in folder.rglob('*') if p.is_file())
  fingerprints=json.loads((folder/'sources.sha256.json').read_text(encoding='utf-8'))
  for name in fingerprints:
   if not name.startswith('generated:'):files.add(within(root,name))
 hashes={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
 return {'accepted':True,'manifest':manifest.relative_to(root).as_posix(),'positive_native_tests':result['positive_unique_native_tests'],'strict_normal_ending_mutants':result['strict_normal_ending_mutants'],'committed_proof_dependencies':len(hashes)},hashes

def unchanged(root,hashes):
 return all((root/name).is_file() and hashlib.sha256((root/name).read_bytes()).hexdigest()==value for name,value in hashes.items())
