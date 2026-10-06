# TD SWUG200: get_regs resolves RTL Q nets to mapped registers. Exceptions
# target first synchronizer stages only; second stages keep ordinary STA.
set_false_path -from [get_ports {rst_n}]
set_false_path -to [get_regs {core/video/display/config_mailbox/req_meta core/video/display/config_mailbox/ack_meta core/video/display/fetch/frame_request/req_meta core/video/display/fetch/frame_request/ack_meta core/video/display/fetch/arm_sync/meta core/video/display/swaps/req_sync[0] core/video/display/swaps/fs_sync[0] core/video/display/swaps/ack_sync[0]}]
# Assertion permission crosses into RESET synchronizers, never ordinary CEs.
set_false_path -from [get_clocks {pixel}] -to [get_pins {core/video/display/fetch/fetch_mem_reset/*.sr}]
set_false_path -from [get_clocks {mem}] -to [get_pins {core/video/display/fetch/fetch_pixel_reset/*.sr}]
# TD can share equivalent reset stages and rename them under another LUT.
# Bound this exception to the JOINED async assertion NET and async SR pins;
# ordinary Q->D/CE paths and synchronized release stages retain normal STA.
set_false_path -through [get_nets {core/video/display/fetch/common_reset_n}] -to [get_pins {*/*.sr}]
# Official FIFO has its own async-assert/sync-release reset stages.
set_false_path -from [get_clocks {mem}] -to [get_regs {core/video/display/fetch/fifo/fifo/asy_r_rst*}]
# Bundled data held until ACK. Bound propagation to8ns, substantially less than
# the ≥2 destination-edge settle interval. datapath_only also removes hold
# phase checks for these intentional asynchronous captures (official TD rule).
set_max_delay -datapath_only -from [get_regs {core/video/display/config_mailbox/payload*}] -to [get_regs {core/video/display/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/display/fetch/frame_request/payload*}] -to [get_regs {core/video/display/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/swap_ctrl/slot_id* core/video/swap_ctrl/generation* core/video/swap_ctrl/frame_index core/video/swap_ctrl/crc_ok}] -to [get_regs {core/video/display/swaps/mb_slot_id_a_r* core/video/display/swaps/mb_generation_a_r* core/video/display/swaps/mb_frame_index_a_r core/video/display/swaps/mb_crc_ok_a_r}] 8.000
# Gray bus propagation < fastest source period (mem8ns, pixel≥13.468ns).
# No false path on these pointers; skew is bounded by the full bus max delay.
set_max_delay -datapath_only -from [get_regs {core/video/display/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/video/display/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/video/display/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/video/display/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000

# New SYS -> PIXEL atomic emergency command mailbox: first stages only.
set_false_path -to [get_regs {core/emergency_control/mailbox/req_meta core/emergency_control/mailbox/ack_meta}]
set_max_delay -datapath_only -from [get_regs {core/emergency_control/mailbox/payload*}] -to [get_regs {core/emergency_control/mailbox/dst_data*}] 8.000
