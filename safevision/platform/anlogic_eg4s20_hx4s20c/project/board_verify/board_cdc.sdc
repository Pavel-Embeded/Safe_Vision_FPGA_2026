# Board bring-up CDC exceptions. Mirrors ab_core_verify/cdc.sdc (the instance is
# named "core" there and here) and adds the board-level reset epoch crossings.
# Only intentional asynchronous crossings are exempted; business logic still
# gets full STA. Do NOT add blanket clock-group false paths.
set_false_path -from [get_ports {rst_n}]

# ---- Board-level reset: one assertion epoch, released per domain ----
# reset_ref runs on board_clk; reset_mem / reset_pixel are the per-domain
# release synchronizers. The asynchronous ASSERTION edge is intentional and is
# why each domain has its own synchronizer. Release paths inside each
# reset_sync keep normal STA.
# Bound through the JOINED async-assert net to the async SR pins, which is the
# form that actually resolves in TD (get_regs on the kept release_pipe array
# did not match and silently applied nothing).
set_false_path -through [get_nets {common_rst_n}] -to [get_pins {*/*.sr}]

# ---- mem -> sys submit toggle (frame_ready) ----
# The mem-domain write completion is published as a toggle and synchronized in
# sys_clk. Only the first synchronizer stage input is exempt.
set_false_path -to [get_regs {submit_sync[0]}]

# ---- Inside safevision_core (same structure A constrained) ----
set_false_path -to [get_regs {core/display/config_mailbox/req_meta core/display/config_mailbox/ack_meta core/display/fetch/frame_request/req_meta core/display/fetch/frame_request/ack_meta core/display/fetch/arm_sync/meta core/display/swaps/req_sync[0] core/display/swaps/fs_sync[0] core/display/swaps/ack_sync[0]}]
set_false_path -from [get_clocks {video_base$video_pll/pll_inst.clkc[1]}] -to [get_pins {core/display/fetch/fetch_mem_reset/*.sr}]
set_false_path -from [get_clocks {system_pll/pll_inst.clkc[1]}] -to [get_pins {core/display/fetch/fetch_pixel_reset/*.sr}]
set_false_path -through [get_nets {core/display/fetch/common_reset_n}] -to [get_pins {*/*.sr}]
set_false_path -from [get_clocks {system_pll/pll_inst.clkc[1]}] -to [get_regs {core/display/fetch/fifo/fifo/asy_r_rst*}]
# Bundled-data mailboxes: bound propagation instead of exempting (same 8 ns as A).
set_max_delay -datapath_only -from [get_regs {core/display/config_mailbox/payload*}] -to [get_regs {core/display/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/frame_request/payload*}] -to [get_regs {core/display/fetch/frame_request/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/swap_ctrl/slot_id* core/swap_ctrl/generation* core/swap_ctrl/frame_index core/swap_ctrl/crc_ok}] -to [get_regs {core/display/swaps/mb_slot_id_a_r* core/display/swaps/mb_generation_a_r* core/display/swaps/frame_index_a_r core/display/swaps/mb_crc_ok_a_r}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/fifo/fifo/wr_to_rd*/primary_addr_gray_reg*}] -to [get_regs {core/display/fetch/fifo/fifo/wr_to_rd*/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {core/display/fetch/fifo/fifo/rd_to_wr*/primary_addr_gray_reg*}] -to [get_regs {core/display/fetch/fifo/fifo/rd_to_wr*/sync_r1*}] 8.000

# ---- HDMI serializer / DDC are vendor-boundary domains ----
# The 4x/5x serializer samples with I_serial_clk from the same VCO; those
# intentional phase relationships are not a false path, so nothing is added
# here. DDC is an I2C boundary and is left to ordinary STA.
