# Normal Tcl only. Not read_sdc. Object matches are not timing closure.
set ::v3_audit_log [open constraint.objects.tsv w]
puts $::v3_audit_log "label\tmatched_objects"
proc v3_expect_objects {label objects} {
 if {[llength $objects]==0} {error "V3 empty mapped collection: $label"}
 puts $::v3_audit_log "$label\t[llength $objects]"
}
v3_expect_objects {first_stage_synchronizers} [get_regs {*req_meta *ack_meta frame_heartbeat_sync/meta pll_loss_sync/meta locks_meta* video/media_m1 video/media_p1 video/safe_p1 video/fault_s1 video/fault_p1 video/present_s1 video/cache/pixel_fault_meta video/cache/*store/done_meta video/cache/*store/fault_meta}]
v3_expect_objects {asynchronous_reset_roots} [get_nets {control_common_rst_n config_common_rst_n media_common_rst_n tx_reset}]
v3_expect_objects {scrolling*status_mailbox.payload} [get_regs {scrolling*status_mailbox/payload*}]
v3_expect_objects {scrolling*status_mailbox.capture} [get_regs {scrolling*status_mailbox/dst_data*}]
v3_expect_objects {uptime_to_pixel.payload} [get_regs {uptime_to_pixel/payload*}]
v3_expect_objects {uptime_to_pixel.capture} [get_regs {uptime_to_pixel/dst_data*}]
v3_expect_objects {hdmi_status_mailbox.payload} [get_regs {hdmi_status_mailbox/payload*}]
v3_expect_objects {hdmi_status_mailbox.capture} [get_regs {hdmi_status_mailbox/dst_data*}]
v3_expect_objects {video/config_mailbox.payload} [get_regs {video/config_mailbox/payload*}]
v3_expect_objects {video/config_mailbox.capture} [get_regs {video/config_mailbox/dst_data*}]
v3_expect_objects {diagnostics/requests.payload} [get_regs {diagnostics/requests/payload*}]
v3_expect_objects {diagnostics/requests.capture} [get_regs {diagnostics/requests/dst_data*}]
v3_expect_objects {diagnostics/responses.payload} [get_regs {diagnostics/responses/payload*}]
v3_expect_objects {diagnostics/responses.capture} [get_regs {diagnostics/responses/dst_data*}]
v3_expect_objects {video/audio_ready_mailbox.payload} [get_regs {video/audio_ready_mailbox/payload*}]
v3_expect_objects {video/audio_ready_mailbox.capture} [get_regs {video/audio_ready_mailbox/dst_data*}]
v3_expect_objects {video/status_mailbox.payload} [get_regs {video/status_mailbox/payload*}]
v3_expect_objects {video/status_mailbox.capture} [get_regs {video/status_mailbox/dst_data*}]
v3_expect_objects {video/cache/requests.payload} [get_regs {video/cache/requests/payload*}]
v3_expect_objects {video/cache/requests.capture} [get_regs {video/cache/requests/dst_data*}]
v3_expect_objects {video/cache/responses.payload} [get_regs {video/cache/responses/payload*}]
v3_expect_objects {video/cache/responses.capture} [get_regs {video/cache/responses/dst_data*}]
v3_expect_objects {audio/ring_to_ref.payload} [get_regs {audio/ring_to_ref/payload*}]
v3_expect_objects {audio/ring_to_ref.capture} [get_regs {audio/ring_to_ref/dst_data*}]
v3_expect_objects {audio/index_to_sys.payload} [get_regs {audio/index_to_sys/payload*}]
v3_expect_objects {audio/index_to_sys.capture} [get_regs {audio/index_to_sys/dst_data*}]
v3_expect_objects {audio/index_to_mem.payload} [get_regs {audio/index_to_mem/payload*}]
v3_expect_objects {audio/index_to_mem.capture} [get_regs {audio/index_to_mem/dst_data*}]
v3_expect_objects {audio/commit_to_mem.payload} [get_regs {audio/commit_to_mem/payload*}]
v3_expect_objects {audio/commit_to_mem.capture} [get_regs {audio/commit_to_mem/dst_data*}]
v3_expect_objects {audio/ready_to_sys.payload} [get_regs {audio/ready_to_sys/payload*}]
v3_expect_objects {audio/ready_to_sys.capture} [get_regs {audio/ready_to_sys/dst_data*}]
v3_expect_objects {audio/control_to_audio.payload} [get_regs {audio/control_to_audio/payload*}]
v3_expect_objects {audio/control_to_audio.capture} [get_regs {audio/control_to_audio/dst_data*}]
v3_expect_objects {audio/status_to_sys.payload} [get_regs {audio/status_to_sys/payload*}]
v3_expect_objects {audio/status_to_sys.capture} [get_regs {audio/status_to_sys/dst_data*}]
v3_expect_objects {wr_to_rd.gray} [get_regs {*wr_to_rd*primary_addr_gray_reg*}]
v3_expect_objects {wr_to_rd.meta} [get_regs {*wr_to_rd*sync_r1*}]
v3_expect_objects {rd_to_wr.gray} [get_regs {*rd_to_wr*primary_addr_gray_reg*}]
v3_expect_objects {rd_to_wr.meta} [get_regs {*rd_to_wr*sync_r1*}]
v3_expect_objects {sink_frame_first} [get_regs {sink/fa_sync[0] sink/td_sync[0] sink/sl_sync[0] sink/sl_sync[1]}]
v3_expect_objects {player_completion_first} [get_regs {player/mr_sync[0] player/fd_sync[0] player/lok_sync[0]}]
v3_expect_objects {spi_receive_input_boundary} [get_pins {sd_miso_syn_*.ipad}]
v3_expect_objects {related_status.ref} [get_regs {ref_status_capture/data*}]
v3_expect_objects {related_status.mem} [get_regs {mem_status_capture/data*}]
v3_expect_objects {related_status.mem_activity} [get_regs {mem_activity/tag*}]
v3_expect_objects {related_clock_packet.packet_data} [get_regs {video/cache/*store/packet_data*}]
v3_expect_objects {related_clock_packet.packet_position} [get_regs {video/cache/*store/packet_position*}]
v3_expect_objects {related_clock_packet.packet_stream} [get_regs {video/cache/*store/packet_stream*}]
v3_expect_objects {related_clock_packet.packet_last} [get_regs {video/cache/*store/packet_last*}]
v3_expect_objects {related_clock_packet.request_toggle} [get_regs {video/cache/*store/request_toggle*}]
v3_expect_objects {related_clock_packet.high_data} [get_regs {video/cache/*store/high_data*}]
v3_expect_objects {related_clock_packet.high_position} [get_regs {video/cache/*store/high_position*}]
v3_expect_objects {related_clock_packet.high_pending} [get_regs {video/cache/*store/high_pending*}]
v3_expect_objects {related_clock_packet.seen_toggle} [get_regs {video/cache/*store/seen_toggle*}]
v3_expect_objects {presentation_fault.first} [get_regs {video/present_s1}]
v3_expect_objects {presentation_fault.second} [get_regs {video/present_s2}]
v3_expect_objects {registered_reset.media} [get_regs {supervisor/recovery/media_reset_q*}]
v3_expect_objects {registered_reset.wav_kernel} [get_regs {audio/source/kernel_release_q*}]
v3_expect_objects {registered_owner.filesystem} [get_regs {player/service_owner_q*}]
v3_expect_objects {frame_safe.source} [get_regs {video/frame_safe_boundary*choose_safe/raw_selected*}]
v3_expect_objects {frame_safe.output} [get_regs {video/frame_safe_boundary*choose_safe/output_selected*}]
proc v3_exact_register_bits {stem} {
 set matches {}
 set expression [format {^sink/u_bridge/writer/%s\[[0-9]+\]$} $stem]
 foreach name [get_regs [format {sink/u_bridge/writer/%s*} $stem]] {
  if {$name eq "sink/u_bridge/writer/$stem" || [regexp $expression $name]} {lappend matches $name}
 }
 return $matches
}
set v3_sample_src [v3_exact_register_bits crc_pair_q]
set v3_sample_bus [v3_exact_register_bits wr_data_r]
set v3_sample_fault [v3_exact_register_bits sample_mismatch]
v3_expect_objects {exact_sample.source} $v3_sample_src
v3_expect_objects {exact_sample.bus} $v3_sample_bus
v3_expect_objects {exact_sample.fault} $v3_sample_fault
if {[llength $v3_sample_src]!=32 || [llength $v3_sample_bus]!=32 || [llength $v3_sample_fault]!=1} {error "V3 exact-sample Q-net width changed"}
foreach v3_sample_net $v3_sample_src {if {[lsearch -exact $v3_sample_bus $v3_sample_net]>=0} {error "V3 source/bus Q nets aliased"}}
unset v3_sample_src v3_sample_bus v3_sample_fault v3_sample_net
close $::v3_audit_log
unset ::v3_audit_log
