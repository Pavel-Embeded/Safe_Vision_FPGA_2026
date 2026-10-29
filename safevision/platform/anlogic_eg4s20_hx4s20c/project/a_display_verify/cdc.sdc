

set_false_path -from [get_ports {rst_n}]
set_false_path -to [get_regs {core/config_mailbox/req_meta core/config_mailbox/ack_meta core/fetch/frame_request/req_meta core/fetch/frame_request/ack_meta core/fetch/arm_sync/meta core/swaps/req_sync[0]}]

set_false_path -from [get_clocks {pixel}] -to [get_pins {core/fetch/fetch_mem_reset/*.sr}]
set_false_path -from [get_clocks {mem}] -to [get_pins {core/fetch/fetch_pixel_reset/*.sr}]

set_false_path -from [get_clocks {mem}] -to [get_regs {core/fetch/fifo/fifo/asy_r_rst*}]


set_max_delay -datapath_only -from [get_regs {core/config_mailbox/payload*}] -to [get_regs {core/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/fetch/frame_request/payload*}] -to [get_regs {core/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {control*}] -to [get_regs {core/swaps/mb_slot_id_a_r* core/swaps/mb_generation_a_r* core/swaps/mb_frame_index_a_r core/swaps/mb_crc_ok_a_r}] 8.000


set_max_delay -datapath_only -from [get_regs {core/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000
