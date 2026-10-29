


set_false_path -from [get_ports {rst_n}]


set_false_path -through [get_nets {common_rst_n}] -to [get_pins {*/*.sr}]


set_false_path -to [get_regs {submit_sync[0]}]


set_false_path -to [get_regs {core/video/display/config_mailbox/req_meta core/video/display/config_mailbox/ack_meta core/video/display/fetch/frame_request/req_meta core/video/display/fetch/frame_request/ack_meta core/video/display/fetch/arm_sync/meta core/video/display/swaps/req_sync[0] core/video/display/swaps/fs_sync[0] core/video/display/swaps/ack_sync[0]}]
set_false_path -from [get_clocks {video_*$video_pll/pll_inst.clkc[1]}] -to [get_pins {core/video/display/fetch/fetch_mem_reset/*.sr}]
set_false_path -from [get_clocks {system_pll/pll_inst.clkc[1]}] -to [get_pins {core/video/display/fetch/fetch_pixel_reset/*.sr}]
set_false_path -through [get_nets {core/video/display/fetch/common_reset_n}] -to [get_pins {*/*.sr}]
set_false_path -from [get_clocks {system_pll/pll_inst.clkc[1]}] -to [get_regs {core/video/display/fetch/fifo/fifo/asy_r_rst*}]

set_max_delay -datapath_only -from [get_regs {core/video/display/config_mailbox/payload*}] -to [get_regs {core/video/display/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/display/fetch/frame_request/payload*}] -to [get_regs {core/video/display/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/swap_ctrl/slot_id* core/video/swap_ctrl/generation* core/video/swap_ctrl/frame_index core/video/swap_ctrl/crc_ok}] -to [get_regs {core/video/display/swaps/mb_slot_id_a_r* core/video/display/swaps/mb_generation_a_r* core/video/display/swaps/frame_index_a_r core/video/display/swaps/mb_crc_ok_a_r}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/display/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/video/display/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/display/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/video/display/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000


set_false_path -to [get_regs {core/emergency_control/mailbox/req_meta core/emergency_control/mailbox/ack_meta}]
set_max_delay -datapath_only -from [get_regs {core/emergency_control/mailbox/payload*}] -to [get_regs {core/emergency_control/mailbox/dst_data*}] 8.000


set_false_path -through [get_nets {hdmi/tx_reset}] -to [get_pins {*/*.sr}]
