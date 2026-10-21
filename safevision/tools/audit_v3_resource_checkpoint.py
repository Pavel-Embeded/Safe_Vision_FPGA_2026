"""Portable audit of exact-source native functional evidence; no STA claim."""
import argparse,hashlib,json,re,sys
from pathlib import Path
from audit_v3_raw_logs import audit_file
ROOT=Path(__file__).resolve().parents[2]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def within(root,name):
 p=(root/name).resolve()
 if not p.is_relative_to(root.resolve()):raise ValueError('evidence/source path escaped root')
 return p

def sources(root,folder,negative=None):
 before=read(folder/'sources.sha256.json');assert before
 after=folder/'sources.after.sha256.json'
 if after.exists():assert read(after)==before,'source changed during test'
 changes=0
 for name,digest in before.items():
  assert re.fullmatch('[0-9a-f]{64}',digest)
  p=within(folder,name.split(':',1)[1]) if name.startswith('generated:') else within(root,name)
  if negative and digest==negative['mutated_sha256']:
   assert sha(p)==negative['original_sha256'],'negative baseline changed'
   assert sha(within(folder,negative['mutant_file']))==digest,'missing exact mutant bytes'
   changes+=1
  else:assert p.is_file() and sha(p)==digest,'current source/input differs: '+name
 if negative:assert changes==1,'negative source binding ambiguous'
 return len(before)

def audit(root,manifest):
 if not __debug__:raise RuntimeError('native acceptance audit requires Python assertions enabled')
 j=read(manifest);assert j['schema']==1 and j['complete']
 prior=read(root/'evidence/v3/current_100_20261016/selected_acceptance.json')
 required=set(prior['unique_tops'])|{'tb_v3_command_catalog','tb_v3_uart_link_catalog'}
 core=(root/'safevision/rtl/video/v3_video_display_core.v').read_text(encoding='utf-8')
 if 'v3_scaler_bilinear_thirds s' in core:required.add('tb_v3_thirds_scaler')
 reset=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v').read_text(encoding='utf-8')
 supervisor=(root/'safevision/rtl/control/v3_supervisor.v').read_text(encoding='utf-8')
 if 'RELEASE_FALLING' in reset:required.add('tb_v3_reset_release_phase')
 if 'reg[32:0] video_limit,audio_limit' in supervisor:required.add('tb_v3_supervisor_threshold')
 if 'begin:compare_byte' in supervisor:required.add('tb_v3_supervisor_comparator')
 audio=(root/'safevision/rtl/audio/v3_audio_system.v').read_text(encoding='utf-8')
 if 'v3_audio_prefill_compare #' in audio:required.add('tb_v3_audio_prefill_compare')
 top=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text(encoding='utf-8')
 if 'v3_phy_reset_fanout reset_phy(' in top:required.update({'tb_v3_phy_reset_fanout','tb_v3_phy_lane_equivalence'})
 if 'B_QUERY_UARTDROP' in top:required.add('tb_v3_board_query_catalog')
 receiver=(root/'safevision/rtl/common/uart_rx.v').read_text(encoding='utf-8')
 controls=(root/'safevision/rtl/control/v3_user_controls.v').read_text(encoding='utf-8')
 player=(root/'safevision/rtl/storage/sd_bmp_player.v').read_text(encoding='utf-8')
 if 'BOUNDED_ACC' in receiver:required.add('tb_v3_uart_rx_equivalence')
 if 'NAME_BRIGHT:' in controls:required.add('tb_v3_control_decode_equivalence')
 if 'decode_catalog(catalog_id)' in controls:required.add('tb_v3_control_catalog_equivalence')
 if '.HANDBOOK_PROFILE(1)' in top:
  required.update({'tb_v3_handbook_controls','tb_v3_response_timer','tb_v3_handbook_coords','tb_v3_handbook_packed',
   'tb_v3_handbook_board','tb_v3_handbook_hud','tb_v3_handbook_video_base','tb_v3_handbook_video_hd',
   'tb_v3_handbook_cfg_atomic','tb_v3_volume_dsp_equivalence','tb_v3_pixel_response_tracker',
   'tb_v3_file_lba_equivalence','tb_v3_controls_pipeline_equivalence','tb_v3_uart_formatter_equivalence','tb_v3_uart_tx_width_equivalence','tb_v3_audio_media_root_equivalence','tb_v3_handbook_energy','tb_v3_handbook_audio_energy','tb_v3_service_owner_equivalence','tb_v3_frame_safe_base','tb_v3_frame_safe_hd','tb_v3_frame_safe_integration'})
 walker=(root/'safevision/rtl/storage/fat32_cluster_walker.v').read_text(encoding='utf-8')
 if '(&fat_off[8:2])' in walker:required.add('tb_v3_walker_assemble_equivalence')
 if 'reg media_reset_q;' in (root/'safevision/rtl/control/media_recovery_ctrl.v').read_text(encoding='utf-8'):
  required.update({'tb_v3_registered_recovery_reset','tb_v3_registered_wav_reset'})
 if '.MID_REF_SAMPLE(1)' in top:
  required.update({'tb_v3_spi25_profile','tb_v3_shared_storage_spi25'})
 if 'v3_hd_coord_arith #' in core:required.add('tb_v3_hd_coord_arith')
 ring=(root/'safevision/rtl/audio/v3_pcm_ring.v').read_text(encoding='utf-8')
 if 'begin:parallel_pointers' in ring:required.update({'tb_v3_pcm_ring_equivalence','tb_v3_pcm_ring_fullwidth_equivalence'})
 context=(root/'safevision/rtl/storage/v3_cluster_walker_ctx.v').read_text(encoding='utf-8')
 if 'function unsigned_ge32' in context:required.add('tb_v3_walker_loop_equivalence')
 if (root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board_sources_hd.list').exists():
  required.update({'tb_v3_hd_handbook_board', 'tb_v3_hd_handbook_video', 'tb_v3_hd_recovery_counter_equivalence', 'tb_v3_hd_status_raster_equivalence', 'tb_v3_hd_pending_or', 'tb_v3_hd_supervisor_alert_equivalence', 'tb_v3_hd_uart_link_catalog', 'tb_v3_hd_video_final', 'tb_v3_hd_row_crc_balance', 'tb_v3_hd_packed_rows', 'tb_v3_hd_uart_link', 'tb_v3_hd_uart_formatter_equivalence'})
 if (root/'safevision/rtl/hd/v3_row_integrity.v').exists():required.update({'tb_v3_hd_guard_2_64', 'tb_v3_hd_guard_480_320', 'tb_v3_hd_guard_255_320', 'tb_v3_hd_guard_3_128', 'tb_v3_hd_guard_256_128', 'tb_v3_hd_guard_5_320'})
 if (root/'safevision/rtl/hd/alpha_blend.v').exists():
  required.add('tb_v3_hd_alpha_equivalence')
  proof=read(root/'evidence/v3/handbook_26101901/alpha_math/exhaustive.json')
  assert proof['accepted']and proof['comparisons']==2621440 and proof['rtl_sha256']==sha(root/'safevision/rtl/hd/alpha_blend.v')
 if (root/'safevision/rtl/hd/v3_supervisor.v').exists():required.add('tb_v3_hd_priority_groups')
 if (root/'safevision/rtl/hd/hdmi_acr.v').exists():
  required.add('tb_v3_hd_acr_equivalence')
  required.update({'tb_v3_hd_crc_preimage','tb_v3_hd_guard_decode','tb_v3_hd_supervisor_windows'})
 if 'led_release_half' in top:
  required.update({'tb_v3_led_publication','tb_v3_led_stopped_reset'})
 if 'greater_bytes' in (root/'safevision/rtl/media/v3_wav_parser_compact_ctx.v').read_text(encoding='utf-8'):
  required.add('tb_v3_wav_bounds_equivalence')
 if 'pair_credit_product' in (root/'safevision/rtl/audio/v3_pcm_ingress_shared_fifo.v').read_text(encoding='utf-8'):
  required.add('tb_v3_ingress_credit')
 if (root/'safevision/rtl/hd/v3_command_parser_catalog.v').exists():
  required.update({'tb_v3_catalog_csa_math','tb_v3_hd_command_catalog'})
  freeze=read(root/'safevision/verification/models/hd_command_catalog_stimulus.freeze.json')
  assert sha(root/freeze['original'])==freeze['original_sha256'] and sha(root/freeze['derived'])==freeze['derived_sha256']
  assert (root/freeze['derived']).read_text().replace('tb_v3_hd_command_catalog','tb_v3_command_catalog')==(root/freeze['original']).read_text()
  math=read(root/'evidence/v3/handbook_26101901/catalog_csa19/exhaustive.json')
  assert math['accepted'] and math['comparisons']==268435456 and math['mismatches']==0
  assert sha(root/'safevision/rtl/hd/v3_command_parser_catalog.v')==math['candidate_sha256']
 if 'VOLUME_COLUMNS(1)' in (root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text():
  required.update({'tb_v3_volume_columns_base','tb_v3_volume_columns_hd','tb_v3_volume_columns_raster'})
  required.update({'tb_v3_volume_columns_vblank_base','tb_v3_volume_columns_vblank_hd'})
  a=(root/'safevision/rtl/video/v3_status_layers.v').read_text().split('module v3_volume_column #',1)[1]
  b=(root/'safevision/rtl/hd/v3_status_layers.v').read_text().split('module v3_volume_column #',1)[1]
  assert a==b,'BASE and HD must use identical shared volume-column calculation'

 if (root/'safevision/rtl/hd/sdram_app_adapter.v').exists():
  required.update({'tb_v3_hd_read64','tb_v3_hd_read64_short','tb_v3_hd_read64_long','tb_v3_hd_read64_basic',
   'tb_v3_hd_stream_budget_0_lat4','tb_v3_hd_stream_budget_1_lat4','tb_v3_hd_stream_budget_2_lat4','tb_v3_hd_stream_budget_3_lat4','tb_v3_hd_stream_budget_0_lat11'})
  for meta in read(root/'safevision/verification/models/hd_read64_stimulus.freeze.json'):
   assert meta['original_source_commit']=='f734af34d075fbe584572b37de47522d3e37eac3'
   assert sha(within(root,meta['original_path']))==meta['original_sha256']
   p=within(root,meta['copy_path']);raw=p.read_bytes();assert sha(p)==meta['reference_sha256']
   for before,after in meta['namespace_only']:raw=raw.replace(after.encode(),before.encode())
   assert hashlib.sha256(raw).hexdigest()==meta['original_sha256'],'read64 stimulus changed beyond namespace'
 seen=set();rows=[]
 for row in j['positive_tests']:
  assert row['top'] not in seen;seen.add(row['top'])
  folder=within(root,row['evidence']);metadata=read(folder/'result.json')
  assert metadata['top']==row['top'] and metadata['accepted_native_runner'] and not metadata['source_overrides']
  assert sha(folder/'result.json')==row['result_sha256']
  count=sources(root,folder);raw=audit_file(folder/'sim.log',not row['legacy'])
  assert raw['accepted'],raw
  rows.append({'top':row['top'],'source_bindings_checked':count,'raw_log_sha256':raw['sha256']})
 assert seen==required,('required tests missing/extra',sorted(required-seen),sorted(seen-required))
 mutants=[]
 for row in j['negative_controls']:
  folder=within(root,row['evidence']);case=read(folder/'case.json')
  assert case['detected'] and case['normal_completion'];sources(root,folder,case)
  text=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
  assert '$finish called' in text and '[FAIL' in text
  assert re.search(r'PASS\s+'+re.escape(case['top'])+r'\b|\[TB\]\s*'+re.escape(case['top'])+r'\s+done',text)
  assert not re.search(r'(?im)^\s*(?:Fatal:|FATAL\b|ERROR:|SKIP\b)',text) and '[SKIP]' not in text
  values=[int(x) for x in re.findall(r'errors\s*=\s*(\d+)',text)]
  assert values==case['error_counts'] and any(values)
  if case.get('required_marker'):assert case['required_marker'] in text
  assert case['mutation'] not in mutants;mutants.append(case['mutation'])
 if (root/'safevision/rtl/hd/sdram_app_adapter.v').exists():assert {'hd_read64_capacity_regression','hd_read64_payload_corrupt','hd_read64_leading_filter'}.issubset(mutants),'HD read-bank changes require deadline and data corruption controls'
 assert len(mutants)>=13
 if (root/'safevision/rtl/hd/hdmi_acr.v').exists():
  assert {'hd_acr_carry_early','hd_acr_saturation_late'}.issubset(mutants),'HD ACR carry/saturation need normal-ending semantic controls'
 if 'greater_bytes' in (root/'safevision/rtl/media/v3_wav_parser_compact_ctx.v').read_text(encoding='utf-8'):
  assert {'odd_pad_lost','wrong_file_bound'}.issubset(mutants),'WAV bound reformulation needs independent odd-padding/file-limit controls'
 if 'pair_credit_product' in (root/'safevision/rtl/audio/v3_pcm_ingress_shared_fifo.v').read_text(encoding='utf-8'):
  assert {'credit_bias_lost','credit_wrong_slice'}.issubset(mutants),'reciprocal credit requires bias and slice semantic controls'
 if (root/'safevision/rtl/hd/v3_supervisor.v').exists():assert 'hd_priority_first_grant_missing' in mutants,'complete queue priority sweep needs a normally detected grant-loss control'
 if (root/'safevision/rtl/hd/v3_command_parser_catalog.v').exists():assert 'hd_decimal_times8' in mutants
 if 'VOLUME_COLUMNS(1)' in (root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v').read_text():
  assert {'volume_column_gain_ignored','volume_column_grows_down'}.issubset(mutants)

 if (root/'safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board_sources_hd.list').exists():
  assert {'hd_recovery_reset_short', 'hd_recovery_done_priority', 'hd_alert_drop_info', 'hd_recovery_timeout_late', 'hd_hud_header_missing', 'hd_alert_late', 'hd_packed_stride', 'hd_row_crc_basis', 'hd_formatter_A', 'hd_packed_selector', 'hd_packed_row_alias', 'hd_hud_menu_alias', 'hd_event_timestamp', 'hd_hud_column_phase', 'hd_row_crc_no_state', 'hd_pending_or_drop10'}.issubset(mutants),'HD implementations require independent semantic corruption controls'
  if (root/'safevision/rtl/hd/v3_row_integrity.v').exists():assert {'hd_guard_slot_alias','hd_guard_read_old_stride','hd_guard_lookup_row_alias'}.issubset(mutants),'signature layout needs semantic corruption controls'
  if 'reg[43:0] priority_ts' in (root/'safevision/rtl/hd/v3_supervisor.v').read_text(encoding='utf-8'):
   assert {'hd_priority_advance_stuck','hd_priority_timestamp_late'}.issubset(mutants),'same-edge priority state requires advancement and timestamp-bank semantic controls'
  if (root/'safevision/rtl/hd/alpha_blend.v').exists():assert {'hd_alpha_round_boundary','hd_alpha_high_quotient','hd_alpha_latency_short'}.issubset(mutants),'retimed blend requires arithmetic/latency semantic controls'
  from v3_source_profiles import source_list
  from v3_sources import FLOW
  source_list(root,FLOW,'base');source_list(root,FLOW,'hd')
  for name in ['safevision/verification/models/v3_hd_alpha_reference.freeze.json', 'safevision/verification/models/v3_hd_guard_reference.freeze.json', 'safevision/verification/models/v3_hd_status_reference.freeze.json', 'safevision/verification/models/v3_hd_recovery_reference.freeze.json', 'safevision/verification/models/v3_hd_supervisor_reference.freeze.json', 'safevision/verification/models/tb_v3_hd_uart_formatter_equivalence.freeze.json', 'safevision/verification/models/tb_v3_hd_uart_link.freeze.json', 'safevision/verification/models/tb_v3_hd_uart_link_catalog.freeze.json', 'safevision/verification/models/tb_v3_hd_packed_rows.freeze.json', 'safevision/verification/models/tb_v3_hd_handbook_board.freeze.json', 'safevision/verification/models/tb_v3_hd_video_final.freeze.json', 'safevision/verification/models/tb_v3_hd_handbook_video.freeze.json']:
   meta=read(root/name);assert meta['original_source_commit']=='e0467f9b2454783bd3275b0b3311f258e94c2a7e'
   origin=within(root,meta['original_path']);assert sha(origin)==meta['original_sha256']
   reference=within(root,meta.get('copy_path',name.removesuffix('.freeze.json')+'.sv'));raw=reference.read_bytes()
   assert sha(reference)==meta['reference_sha256']
   for before,after in sorted(meta['namespace_only'],key=lambda pair:len(pair[1]),reverse=True):
    assert after.encode()in raw;raw=raw.replace(after.encode(),before.encode())
   assert hashlib.sha256(raw).hexdigest()==meta['original_sha256'],'HD reference/stimulus differs from original beyond namespace/profile parameter'

 if len(required)>=105:
  assert {'positive_phase_release','drop threshold carry33_to32','retimed_rounding','message_snapshot_bit'}.issubset(mutants),'new datapath/phase changes need their strict negative controls'
 if 'begin:compare_byte' in supervisor:
  assert {'lookahead_high_byte','tick_predict_off_by_one'}.issubset(mutants),'lookahead logic needs comparator and tick semantic mutants'
 if 'v3_audio_prefill_compare #' in audio:assert {'prefill_partial_weight','prefill_boundary'}.issubset(mutants),'prefill predicate needs semantic mutants'
 if 'v3_phy_reset_fanout reset_phy(' in top:assert {'phy_release_early','phy_lane_payload'}.issubset(mutants),'lane replication needs reset and serial-data mutants'
 if 'B_QUERY_UARTDROP' in top:assert 'board_query_binding' in mutants,'numeric board queries need binding corruption detection'
 if 'BOUNDED_ACC' in receiver:assert 'uart_fractional_step' in mutants,'bounded UART accumulator needs tick corruption detection'
 if 'NAME_BRIGHT:' in controls:assert {'control_signed_range','control_write_binding'}.issubset(mutants),'control decoding needs signed-boundary and write-binding mutants'
 if 'decode_catalog(catalog_id)' in controls:assert 'control_catalog_binding' in mutants,'board controls need an independently detected catalog-ID binding mutant'
 if '.HANDBOOK_PROFILE(1)' in top:
  assert {'default_auto_disabled','warm_reset_erases_configuration','thumbnail_row_alias','thumbnail_stride_one',
   'brightness_percent_offset','latency_tick_wrong','volume_reciprocal_corrupt','volume_left_published_early','cfg_commits_midframe','response_old_target_allowed','response_startup_allowed',
   'cluster_lba_wrong_bias','cluster_lba_wrong_source','command_argument_alias','command_range_wrong_epoch','formatter_hex_corrupt','uart_tx_counter_too_short','canonical_media_reset_bypass','energy_post_volume_tap','energy_display_gain_removed','energy_release_wrong_rounding','energy_window_short','handbook_energy_profile_disabled','service_owner_inverted','safe_raw_changes_midframe','safe_output_uses_wrong_blank','safe_core_bypasses_frame_choice','safe_graphics_live_flag'}.issubset(mutants),'handbook controls/storage/measurement require strict semantic negative controls'
 if 'tb_v3_registered_wav_reset' in required:
  assert {'combinational_recovery_reset','combinational_kernel_reset','wav_picker_priority'}.issubset(mutants),'registered reset and parallel picker need semantic corruption controls'
 if ".sel_slot(RESIDENT_CACHE?2'd0:pick_slot)" in player:
  assert 'single_candidate_slot_binding' in mutants,'single-candidate lookup must detect an out-of-range slot binding'
 adapter=(root/'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v').read_text(encoding='utf-8')
 if 'write_lead<=wbase[1:0]' in adapter:
  assert {'legacy_two_beat_write_bursts','unaligned_write_start'}.issubset(mutants),'aligned writes require short-group and unaligned-start controls'
 if "physical_words<={wcnt[4:2],2'b00}" in adapter:
  assert 'legacy_two_beat_write_bursts' in mutants,'fourbeat physical writes need the old short-burst semantic control'
 if 'reg event_push_pipe;' in top:assert 'event_timestamp_lost' in mutants,'event register needs atomic timestamp corruption detection'
 if 'b_diag_next0=' in top:assert 'fast_diag_bank_corrupt' in mutants,'fast diagnostic banks need payload corruption detection'
 if 'read_lead<=addr[1:0]' in adapter:assert 'legacy_unaligned_reads' in mutants,'physical read alignment needs old-shape corruption detection'
 parser=(root/'safevision/rtl/control/v3_command_parser_catalog.v').read_text(encoding='utf-8')
 if 'reg timer_expired;' in parser:assert 'parser_timeout_early' in mutants,'registered deadline requires exact-cycle negative control'
 if 'Holding unselected banks' in top:assert 'async_direct_class_corrupt' in mutants,'held inactive data must be fenced by the registered reply class'
 if '(&fat_off[8:2])' in walker:assert 'fat_last_entry_selection' in mutants,'sector-tail selection requires an independently detected last-entry corruption'
 volume=root/'safevision/rtl/audio/v3_audio_volume.v'
 if 'dsp_style="yes"' in volume.read_text(encoding='utf-8'):
  frozen=root/'safevision/verification/models/v3_audio_volume_reference.sv'
  freeze=read(root/'safevision/verification/models/v3_audio_volume_reference.freeze.json')
  assert freeze['original_source_commit']=='4cc88201737df7545d3fdd5b65750bb9011b21c3'
  assert freeze['original_sha256']=='e414ac4070f9907598fa7511b1a60727d27a4197285447fa0b3a8ee3f7b0c28c'
  assert freeze['reference_sha256']==sha(frozen),'frozen independent volume oracle changed'
  original=frozen.read_bytes();name=b'module v3_audio_volume_reference('
  assert original.count(name)==1
  assert hashlib.sha256(original.replace(name,b'module v3_audio_volume(',1)).hexdigest()==freeze['original_sha256'],'reference must be the exact original source with only module name changed'
  # Frozen implementation oracles must recover the exact reviewed original
  # bytes by module-name substitution alone, including original line endings.
  for rel,original_name,reference_name,original_sha in [('safevision/verification/models/v3_file_streamer_compact_reference', 'module v3_file_streamer_compact_ctx (', 'module v3_file_streamer_compact_reference (', '0cfdcc01152d9c8cc4d89188e4a3b77b329f02dd09d9aaf2cb2bfdb19411edb7'), ('safevision/verification/models/v3_controls_pipeline_reference', 'module v3_user_controls #(', 'module v3_controls_pipeline_reference #(', '53de858272cdb008db84d0f5c84507c68dda62a7944bea63654b6cdbea01c2e2'), ('safevision/verification/models/v3_uart_formatter_reference', 'module v3_uart_link #(', 'module v3_uart_formatter_reference #(', 'cc9544fdde296187605de33ac053a8615772bf825bc53a1250459e880b6a473d'), ('safevision/verification/models/v3_uart_tx_reference', 'module uart_tx #(', 'module v3_uart_tx_reference #(', '29ce436b0638005bcd03416b9df7ba379eac71e55f22f47f7caccf366774eeb5')]:
   reference=root/(rel+'.sv');metadata=read(root/(rel+'.freeze.json'));raw=reference.read_bytes()
   assert metadata['original_source_commit']=='17d418e8c76135da438f7a748257d1913820a5e9'
   assert metadata['reference_sha256']==sha(reference) and metadata['original_sha256']==original_sha
   assert raw.count(reference_name.encode())==1
   assert hashlib.sha256(raw.replace(reference_name.encode(),original_name.encode(),1)).hexdigest()==original_sha,'independent reference changed'
  assert 'v3_audio_system #(.EXTERNAL_SERVICE(1),.MEDIA_RESET_INCLUDES_GLOBAL(1),.HANDBOOK_PROFILE(1)) audio(' in top
  assert '.rst_n(control_common_rst_n),.media_reset(!media_common_rst_n),.mounted' in top
  reference=root/'safevision/verification/models/v3_audio_root_reference.sv';metadata=read(reference.with_suffix('.freeze.json'));raw=reference.read_bytes()
  assert metadata['original_source_commit']=='211d85ff038f09f205d94c9deda3ef77e230ad70'
  assert metadata['original_sha256']=='4312221d838301b0180dc6f0ea1152332c7d8f333c88acf2c9ee7380612e2350' and metadata['reference_sha256']==sha(reference)
  assert raw.count(b'module v3_audio_root_reference #(')==1 and raw.count(b'v3_audio_reset_release_reference')==metadata['helper_name_replacements']
  restored=raw.replace(b'module v3_audio_root_reference #(',b'module v3_audio_system #(',1).replace(b'v3_audio_reset_release_reference',b'v3_audio_reset_release')
  assert hashlib.sha256(restored).hexdigest()==metadata['original_sha256'],'audio reset oracle differs from exact original namespace-only copy'
  p=root/'evidence/v3/handbook_26101801/volume_math/exhaustive.json';v=read(p)
  assert v['complete'] and v['integer_values_compared']==838860801 and v['errors']==0
  assert (v['range_min'],v['range_max'],v['magic'],v['shift'],v['rounding_excess'])==(0,838860800,1374389535,37,28)
  assert v['rtl_sha256']==sha(volume) and v['proof_script_sha256']==sha(root/'safevision/tools/check_v3_volume_reciprocal.py'),'exact arithmetic proof/source binding'
 if 'tb_v3_registered_wav_reset' in required:
  for model,original_name,original_sha in (
    ('v3_recovery_reset_reference','media_recovery_ctrl','1b2ea7871b758d9b6d1fde1dfafbc95da151c3d51748cb2b7d7398ec75e3a3ad'),
    ('v3_wav_reset_reference','v3_wav_source','984bc8750fdbba34835fc83f5fa31281e51480380e4fb3d9ab6f082ab0039249')):
   p=root/('safevision/verification/models/'+model+'.sv');raw=p.read_bytes();meta=read(p.with_suffix('.freeze.json'))
   assert meta['original_source_commit']=='3deff7a4cf6aa0e6c0cd8934c4d8e4f93209e292'
   assert meta['original_sha256']==original_sha and meta['reference_sha256']==sha(p)
   token=('module '+model+' #(').encode();assert raw.count(token)==1
   assert hashlib.sha256(raw.replace(token,('module '+original_name+' #(').encode(),1)).hexdigest()==original_sha
 if 'tb_v3_service_owner_equivalence' in required:
  p=root/'safevision/verification/models/v3_player_owner_reference.sv';raw=p.read_bytes();meta=read(p.with_suffix('.freeze.json'))
  assert meta['original_source_commit']=='52f88406e35811638c3ca68ea0a92b8670c7503b'
  assert meta['original_sha256']=='ee6b84f53dbadeb078103f21ee5f10334e209a09de21804a1a66ac778d95cef3' and meta['reference_sha256']==sha(p)
  token=b'module v3_player_owner_reference #(';assert raw.count(token)==1
  assert hashlib.sha256(raw.replace(token,b'module sd_bmp_player #(',1)).hexdigest()==meta['original_sha256']
 if '.MID_REF_SAMPLE(1)' in top:
  assert {'spi25_early_capture','spi25_zero_still_clamped','spi25_reversed_rx_bits'}.issubset(mutants),'SPI25 requires real capture/rate/bit-order corruption controls'
 if 'v3_hd_coord_arith #' in core:assert {'coord_one_pixel_early','coord_missing_startup_mask','coord_wrong_frame_wrap'}.issubset(mutants)
 if 'begin:parallel_pointers' in ring:assert {'ring_wrong_owner','ring_count_plus_two','ring_early_write_completion'}.issubset(mutants)
 if 'function unsigned_ge32' in context:assert {'walker_overflow_guard_removed','walker_equal_hop_allowed','walker_tail_entry_byte_lost'}.issubset(mutants)
 p=root/'safevision/verification/models/v3_pcm_ring_reference.sv';raw=p.read_bytes();meta=read(p.with_suffix('.freeze.json'))
 assert meta['original_source_commit']=='d0f5bd209786ccbf1edc52112d598618515dcea5' and meta['original_sha256']=='1bf284059ab9eea4a838caa00c5c1a6abd9133f62341ec1ea961a85370795f2d' and meta['reference_sha256']==sha(p)
 token=b'module v3_pcm_ring_reference #(';assert raw.count(token)==1
 assert hashlib.sha256(raw.replace(token,b'module v3_pcm_ring #(',1)).hexdigest()=='1bf284059ab9eea4a838caa00c5c1a6abd9133f62341ec1ea961a85370795f2d'
 p=root/'safevision/verification/models/v3_cluster_walker_reference.sv';raw=p.read_bytes();meta=read(p.with_suffix('.freeze.json'))
 assert meta['original_source_commit']=='d0f5bd209786ccbf1edc52112d598618515dcea5' and meta['original_sha256']=='e0c0a839dee6da67503901744b0b6e8e3bc4fabbb8324f7dd44f8fa6bc77adfc' and meta['reference_sha256']==sha(p)
 token=b'module v3_cluster_walker_reference (';assert raw.count(token)==1
 assert hashlib.sha256(raw.replace(token,b'module v3_cluster_walker_ctx (',1)).hexdigest()=='e0c0a839dee6da67503901744b0b6e8e3bc4fabbb8324f7dd44f8fa6bc77adfc'
 return {'accepted':True,'positive_unique_native_tests':len(required),'strict_normal_ending_mutants':len(mutants),'tests':rows,'source_bytes_and_inputs_verified':True,'routed_sta_passed':False,'bitstreams_verified':False,'hardware_verified':False,'release_ready':False}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--repo',type=Path,default=ROOT);ap.add_argument('--manifest',type=Path,default=Path('evidence/v3/resource_113_20261016/acceptance.json'));ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 try:r=audit(a.repo.resolve(),within(a.repo,a.manifest));code=0
 except Exception as ex:r={'accepted':False,'error':str(ex),'release_ready':False};code=1
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2),encoding='utf-8')
 print('RESOURCE CHECKPOINT '+('PASS' if r['accepted'] else 'FAIL'));return code
if __name__=='__main__':sys.exit(main())
