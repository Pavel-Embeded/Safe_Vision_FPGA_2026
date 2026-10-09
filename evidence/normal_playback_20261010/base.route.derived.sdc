create_clock -name board_clk -period 20.000 -waveform {0 10} [get_ports {clk}]
derive_clocks
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {rst_n}]
set_false_path -through [get_nets {common_rst_n}] -to [get_pins {*.sr */*.sr}]
set_false_path -to [get_regs {board_frame_mailbox/req_meta board_frame_mailbox/ack_meta}]
set_max_delay -datapath_only -from [get_regs {board_frame_mailbox/payload*}] -to [get_regs {board_frame_mailbox/dst_data*}] 8.000
set_false_path -to [get_regs {core/display/config_mailbox/req_meta core/display/config_mailbox/ack_meta core/display/fetch/frame_request/req_meta core/display/fetch/frame_request/ack_meta core/display/fetch/arm_sync/meta core/display/swaps/req_sync[0] core/display/swaps/fs_sync[0] core/display/swaps/ack_sync[0]}]
set_false_path -through [get_nets {core/display/fetch/common_reset_n}] -to [get_pins {*.sr */*.sr}]
set_false_path -through [get_nets {core/display/fetch/fifo_reset}] -to [get_pins {*.sr */*.sr}]
set_max_delay -datapath_only -from [get_regs {core/display/config_mailbox/payload*}] -to [get_regs {core/display/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/frame_request/payload*}] -to [get_regs {core/display/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/swap_ctrl/slot_id* core/swap_ctrl/generation* core/swap_ctrl/frame_index core/swap_ctrl/crc_ok}] -to [get_regs {core/display/swaps/mb_slot_id_a_r* core/display/swaps/mb_generation_a_r* core/display/swaps/frame_index_a_r core/display/swaps/mb_crc_ok_a_r}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/display/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/display/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000
set_false_path -to [get_regs {sb_sync[0]}]
set_false_path -to [get_regs {sink_fatal_sync/meta}]
set_max_delay -datapath_only -from [get_regs {reset_mem/release_pipe*}] -to [get_regs {sink/u_fifo/fifo/full_flag}] 8.000
set_false_path -to [get_regs {sink/fa_sync[0] sink/td_sync[0] sink/sl_sync[1:0]}]
set_false_path -to [get_regs {player/mr_sync[0] player/fd_sync[0] player/lok_sync[0]}]
set_false_path -to [get_regs {t_state1* t_fail1* t_ec1* t_ed1* t_r1_1* t_seq_1* t_sd1* t_card1* t_fok1* t_fcnt1* t_cur1* t_bytes1* t_fcnt16_1*}]
set_max_delay -datapath_only -from [get_regs {sink/u_fifo/fifo/wr_to_rd_cross_inst/primary_addr_gray_reg*}] -to [get_regs {sink/u_fifo/fifo/wr_to_rd_cross_inst/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {sink/u_fifo/fifo/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs {sink/u_fifo/fifo/rd_to_wr_cross_inst/sync_r1*}] 8.000
set_false_path -from [get_ports {btn_next btn_auto}]
set_false_path -to [get_regs {display_guard/media_meta display_guard/storage_meta display_guard/manual_meta}]
set_false_path -through [get_nets {tx_reset}] -to [get_pins {*.sr */*.sr}]
set_multicycle_path -setup -from [get_regs {ridx*}] 2
set_multicycle_path -hold -end -from [get_regs {ridx*}] 1
