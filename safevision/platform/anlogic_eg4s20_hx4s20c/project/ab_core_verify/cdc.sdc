

set_false_path -from [get_ports {rst_n}]
set_false_path -to [get_regs {core/display/config_mailbox/req_meta core/display/config_mailbox/ack_meta core/display/fetch/frame_request/req_meta core/display/fetch/frame_request/ack_meta core/display/fetch/arm_sync/meta core/display/swaps/req_sync[0] core/display/swaps/fs_sync[0] core/display/swaps/ack_sync[0]}]

set_false_path -from [get_clocks {pixel}] -to [get_pins {core/display/fetch/fetch_mem_reset/*.sr}]
set_false_path -from [get_clocks {mem}] -to [get_pins {core/display/fetch/fetch_pixel_reset/*.sr}]


set_false_path -through [get_nets {core/display/fetch/common_reset_n}] -to [get_pins {*/*.sr}]

set_false_path -from [get_clocks {mem}] -to [get_regs {core/display/fetch/fifo/fifo/asy_r_rst*}]


set_max_delay -datapath_only -from [get_regs {core/display/config_mailbox/payload*}] -to [get_regs {core/display/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/frame_request/payload*}] -to [get_regs {core/display/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/swap_ctrl/slot_id* core/swap_ctrl/generation* core/swap_ctrl/frame_index core/swap_ctrl/crc_ok}] -to [get_regs {core/display/swaps/mb_slot_id_a_r* core/display/swaps/mb_generation_a_r* core/display/swaps/mb_frame_index_a_r core/display/swaps/mb_crc_ok_a_r}] 8.000


set_max_delay -datapath_only -from [get_regs {core/display/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/display/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/display/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000
