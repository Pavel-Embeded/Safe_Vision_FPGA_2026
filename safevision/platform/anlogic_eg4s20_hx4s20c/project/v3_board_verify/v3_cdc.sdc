


set_false_path -to [get_regs {*req_meta *ack_meta frame_heartbeat_sync/meta pll_loss_sync/meta locks_meta* video/media_m1 video/media_p1 video/safe_p1 video/fault_s1 video/fault_p1 video/present_s1 video/cache/pixel_fault_meta video/cache/*store/done_meta video/cache/*store/fault_meta}]
set_false_path -through [get_nets {control_common_rst_n config_common_rst_n media_common_rst_n tx_reset}] -to [get_pins {*.sr */*.sr}]

set_max_delay -datapath_only -from [get_regs {uptime_to_pixel/payload*}] -to [get_regs {uptime_to_pixel/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {hdmi_status_mailbox/payload*}] -to [get_regs {hdmi_status_mailbox/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {video/config_mailbox/payload*}] -to [get_regs {video/config_mailbox/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {diagnostics/requests/payload*}] -to [get_regs {diagnostics/requests/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {diagnostics/responses/payload*}] -to [get_regs {diagnostics/responses/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {video/audio_ready_mailbox/payload*}] -to [get_regs {video/audio_ready_mailbox/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {video/status_mailbox/payload*}] -to [get_regs {video/status_mailbox/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {video/cache/requests/payload*}] -to [get_regs {video/cache/requests/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {video/cache/responses/payload*}] -to [get_regs {video/cache/responses/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/ring_to_ref/payload*}] -to [get_regs {audio/ring_to_ref/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/index_to_sys/payload*}] -to [get_regs {audio/index_to_sys/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/index_to_mem/payload*}] -to [get_regs {audio/index_to_mem/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/commit_to_mem/payload*}] -to [get_regs {audio/commit_to_mem/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/ready_to_sys/payload*}] -to [get_regs {audio/ready_to_sys/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/control_to_audio/payload*}] -to [get_regs {audio/control_to_audio/dst_data*}] 8.000

set_max_delay -datapath_only -from [get_regs {audio/status_to_sys/payload*}] -to [get_regs {audio/status_to_sys/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {*wr_to_rd*primary_addr_gray_reg*}] -to [get_regs {*wr_to_rd*sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {*rd_to_wr*primary_addr_gray_reg*}] -to [get_regs {*rd_to_wr*sync_r1*}] 8.000

set_false_path -to [get_regs {sink/fa_sync[0] sink/td_sync[0] sink/sl_sync[0] sink/sl_sync[1]}]
set_false_path -to [get_regs {player/mr_sync[0] player/fd_sync[0] player/lok_sync[0]}]


set_multicycle_path -setup -from [get_cells {player/u_bmp/mult0*}] -to [get_regs {player/u_bmp/header_trunc_q}] 2
set_multicycle_path -hold -from [get_cells {player/u_bmp/mult0*}] -to [get_regs {player/u_bmp/header_trunc_q}] 1
