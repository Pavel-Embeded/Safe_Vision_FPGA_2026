# TD SWUG200: get_regs resolves RTL Q nets to mapped registers. Exceptions
# target first synchronizer stages only; second stages keep ordinary STA.
set_false_path -from [get_ports {rst_n}]
set_false_path -to [get_regs {core/config_mailbox/req_meta core/config_mailbox/ack_meta core/fetch/frame_request/req_meta core/fetch/frame_request/ack_meta core/fetch/arm_sync/meta core/swaps/req_sync[0]}]
# Assertion permission crosses into RESET synchronizers, never ordinary CEs.
set_false_path -from [get_clocks {pixel}] -to [get_pins {core/fetch/fetch_mem_reset/*.sr}]
set_false_path -from [get_clocks {mem}] -to [get_pins {core/fetch/fetch_pixel_reset/*.sr}]
# Official FIFO has its own async-assert/sync-release reset stages.
set_false_path -from [get_clocks {mem}] -to [get_regs {core/fetch/fifo/fifo/asy_r_rst*}]
# Bundled data held until ACK. Bound propagation to8ns, substantially less than
# the ≥2 destination-edge settle interval. datapath_only also removes hold
# phase checks for these intentional asynchronous captures (official TD rule).
set_max_delay -datapath_only -from [get_regs {core/config_mailbox/payload*}] -to [get_regs {core/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/fetch/frame_request/payload*}] -to [get_regs {core/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {control*}] -to [get_regs {core/swaps/mb_slot_id_a_r* core/swaps/mb_generation_a_r* core/swaps/mb_frame_index_a_r core/swaps/mb_crc_ok_a_r}] 8.000
# Gray bus propagation < fastest source period (mem8ns, pixel≥13.468ns).
# No false path on these pointers; skew is bounded by the full bus max delay.
set_max_delay -datapath_only -from [get_regs {core/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000
