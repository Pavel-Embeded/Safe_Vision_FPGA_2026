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
set_false_path -through [get_nets {common_rst_n}] -to [get_pins {*.sr */*.sr}]
# Verify nonempty routed exception endpoints after synthesis. Do not replace
# this reset-net exception with a clock-to-all-SR blanket exception.

# ---- MEM -> SYS board frame mailbox ----
# Only the first event/ack synchronizer stages are exempt. Bundled payload
# propagation remains physically bounded and checked after route.
set_false_path -to [get_regs {board_frame_mailbox/req_meta board_frame_mailbox/ack_meta}]
set_max_delay -datapath_only -from [get_regs {board_frame_mailbox/payload*}] -to [get_regs {board_frame_mailbox/dst_data*}] 8.000

# ---- Inside safevision_core (same structure A constrained) ----
set_false_path -to [get_regs {core/display/config_mailbox/req_meta core/display/config_mailbox/ack_meta core/display/fetch/frame_request/req_meta core/display/fetch/frame_request/ack_meta core/display/fetch/arm_sync/meta core/display/swaps/req_sync[0] core/display/swaps/fs_sync[0] core/display/swaps/ack_sync[0]}]
set_false_path -through [get_nets {core/display/fetch/common_reset_n}] -to [get_pins {*.sr */*.sr}]
# The MEM-domain frame flush asynchronously asserts the vendor FIFO read-side
# reset synchronizer. Both reset stages release on pixel_clk inside the IP.
# Only their asynchronous SR pins are exempt; stage D/CE and every FIFO data,
# Gray pointer and local released-reset path remain timed. TD folds fifo_reset
# into state decode, so use the confirmed routed SR endpoint (not an empty net).
# Preserve the raw flush net in RTL so the exception survives TD cell packing.
# It feeds only the vendor reset synchronizers' asynchronous SR inputs. Their
# released resets, D paths, FIFO data and Gray pointers retain ordinary STA.
set_false_path -through [get_nets {core/display/fetch/fifo_reset}] -to [get_pins {*.sr */*.sr}]
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

# sys -> mem: swap-busy level, first synchronizer stage only.
# NOTE: core/swap_ctrl runs on sys_clk (see frame_swap_ctrl.v), so the sink's
# swap_busy input must be the SYNCHRONIZED swap_busy_mem, not swap_state_o.
set_false_path -to [get_regs {sb_sync[0]}]
# MEM fatal swap latch -> 50 MHz player permission; only the metastability stage.
set_false_path -to [get_regs {sink_fatal_sync/meta}]

# ---- Plan A: SD/media chain now runs on the 50 MHz board clock ----
# sd_bmp_player (board_clk, 50 MHz) <-> bmp_frame_sink (mem_clk, 125 MHz).
# The two domains meet at exactly three places, all intentional:
#
# (a) Reset. bmp_frame_sink drives the official pixel FIFO's asynchronous reset
#     from mem_rst_n. Asynchronous assertion is by design and the per-domain
#     synchronous release lives inside the IP (wr_rst_done).
# Keep normal recovery/removal checks on the write-reset synchronizer SR pins.
# The clocks share the board oscillator; the routed release paths pass these
# checks. A physical asy_w_rst*.sr exception can silently become invalid when
# TD packs/renames the cells. It is deliberately absent, rather than replacing
# it with a broader reset or clock exception. Recheck after each route.
# Raw MEM reset also gates wrapper wr_ready. The vendor asy_w_rst0/1 holds
# wr_rst_done=0 and full_flag reset for at least one 20 ns write-clock period
# after raw reset releases. Bound ONLY that reset-origin control to 8 ns,
# inside this protection window. Do not relax the normal full_flag/Gray data.
set_max_delay -datapath_only -from [get_regs {reset_mem/release_pipe*}] -to [get_regs {sink/u_fifo/fifo/full_flag}] 8.000
#
# (b) Frame control, 50 -> 125 MHz: frame_active / top_down / slot are captured by
#     two-stage synchronizers inside the sink. Exempt only the FIRST stage; the
#     payload (top_down/slot) is a bundled-data level that is stable for many
#     source cycles before frame_active rises, so it is sampled safely.
set_false_path -to [get_regs {sink/fa_sync[0] sink/td_sync[0] sink/sl_sync[1:0]}]
#
# (c) Frame control, 125 -> 50 MHz: mem_ready / frame_done / last_frame_ok are
#     captured by two-stage synchronizers inside the player.
set_false_path -to [get_regs {player/mr_sync[0] player/fd_sync[0] player/lok_sync[0]}]
#
# (e) Player telemetry -> mem domain. The UART status line, the card_mode fallback
#     test and the LEDs live on mem_clk, but after Plan A the player's telemetry
#     registers are on board_clk. Reading them combinationally from the mem domain
#     was both a real CDC and 55 violating paths (worst -1.77 ns, logic level 6).
#     Each field now has its own two-stage synchronizer; only the first stage is
#     exempt. The status line is a 500 ms diagnostic refresh, not an atomic
#     snapshot, so a per-bit synchronizer is the appropriate treatment.
set_false_path -to [get_regs {t_state1* t_fail1* t_ec1* t_ed1* t_r1_1* t_seq_1* t_sd1* t_card1* t_fok1* t_fcnt1* t_cur1* t_bytes1* t_fcnt16_1*}]
#
# (d) The 32-bit pixel stream itself crosses ONLY through the official
#     a_pixel_fifo, whose internal Gray-code pointer synchronizers are bounded
#     (not exempted) exactly like the display fetch FIFO above. Its write side is
#     wr_clk = board_clk and its read side is mem_clk.
set_max_delay -datapath_only -from [get_regs {sink/u_fifo/fifo/wr_to_rd_cross_inst/primary_addr_gray_reg*}] -to [get_regs {sink/u_fifo/fifo/wr_to_rd_cross_inst/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {sink/u_fifo/fifo/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs {sink/u_fifo/fifo/rd_to_wr_cross_inst/sync_r1*}] 8.000

# ---- Mechanical push-buttons ----
# Raw KEY2/KEY4 are pulled high; a press pulls low. Two flip-flops precede
# inversion and debounce. No clock budget exists for a mechanical input.
# The first stage is packed into TD's input PAD register and is not returned
# by get_regs. These ports feed ONLY their input synchronizers. A port-origin
# exception ends at that first register; stage-to-stage paths remain timed.
set_false_path -from [get_ports {btn_next btn_auto}]
set_false_path -to [get_regs {display_guard/media_meta display_guard/storage_meta display_guard/manual_meta}]

# HDMI queue overflow asserts transmitter/PHY reset. Only the asynchronous
# assertion into the serial-clock reset synchronizer is exempt; release and
# ODDR paths remain timed. Match both flattened and hierarchical SR names.
set_false_path -through [get_nets {tx_reset}] -to [get_pins {*.sr */*.sr}]

# ---- Slow board outputs with no measured I/O budget yet ----
# sd_dclk (SPI, <=20.8 MHz), sd_mosi, sd_ncs and uart_txd (115200 baud) are
# deliberately left WITHOUT output delay numbers, exactly like the bring-up top
# that already passed routed STA. Add I/O delays once measured on hardware.

# ---- UART status reporter: ridx -> report mux is a true 2-cycle path ----
# Current memory profile is 50 MHz: the same 2-cycle protocol gives a 40 ns
# setup budget and about 4340 clocks/byte. The 125 MHz figures below describe
# the historical 2026-10-06 diagnosis, not the current operating frequency.
# 2026-10-06, mem->mem domino #2 (after the fetch guarded_level cut). The status
# rbyte_c mux spans telemetry sources across the whole die; its select tree is
# driven by ridx (fanout 54, net-dominated 70~73%, worst single-cycle path was
# 8.6 ns / 8.0 ns budget). This is a PHYSICAL SPAN problem: inserting pipeline
# registers behind the mux only moves the same long path to a new endpoint, so
# single-cycle structural cuts cannot fix it. What CAN fix it is more time per
# capture, which the reporter genuinely has:
#   - one byte per ~10850 mem_clk cycles (115200 baud @ 125 MHz);
#   - the FSM now waits one extra cycle after updating ridx before capturing
#     rbyte_c (safevision_top.v rwait), so everything launched by ridx is
#     sampled >=2 cycles after the launch edge;
#   - all other captures in the ridx cone (rload/rbusy/ridx self-increment) are
#     enable-gated holds between byte events: their value at intermediate edges
#     does not depend on freshly-launched ridx data.
# ridx has NO consumers outside the reporter; the odd sink-side endpoints seen
# in STA (sink/sel5..., sink/err_code...) are LUT-site packing artifacts of
# merged report logic (ridx is not a sink port). Relaxed with a real multicycle
# (not a false path), hold moves 1 cycle together with the data.
# VERIFY after every STA run: ridx paths must show Budget 16.000ns in
# legacy route.timing (current 50 MHz: 40 ns); an empty match leaves one period
# (defect 23 lesson: TD does NOT warn on empty collections).
# ★ 2026-10-06 订正（guardfix2 的 route.check 第 4 节实证这两条被判 invalid）：
#   ① get_regs 按 **Q 端 net 名**匹配（SWUG200 §3.1.9），Q 网名是 `ridx[N]`
#      而不是 `ridx_reg*` ⇒ 正确通配是 {ridx*}；
#   ② TD 官方语法（SWUG200 p38-41）数值放**最后**：`... -from [...] 2`；
#   ③ setup N 周期时 hold 需显式补 N-1 且同侧（-end），否则 hold 仍在原边。
set_multicycle_path -setup -from [get_regs {ridx*}] 2
set_multicycle_path -hold -end -from [get_regs {ridx*}] 1

# Writer CRC state feedback only. have_lo/wr_pending make sampled pair events
# at least three clocks apart at full input rate. crc_src_pend consumes the
# pair one edge later. Conservatively allow two clocks from crc_src Q to
# crc_src D; the newly latched crc_pair_q and its enable retain ONE clock.
# Never use crc_src*: it also selects crc_src_pend. Exact 16-bit collections
# are checked after legalize_phy_inst in td_flow.tcl. Regress the contract with
# tb_frame_writer_crc_feedback (stride 1/2/1024, backpressure, pending reset).
set_multicycle_path -setup -end -from [get_regs {fb_writer/crc_src[0] fb_writer/crc_src[1] fb_writer/crc_src[2] fb_writer/crc_src[3] fb_writer/crc_src[4] fb_writer/crc_src[5] fb_writer/crc_src[6] fb_writer/crc_src[7] fb_writer/crc_src[8] fb_writer/crc_src[9] fb_writer/crc_src[10] fb_writer/crc_src[11] fb_writer/crc_src[12] fb_writer/crc_src[13] fb_writer/crc_src[14] fb_writer/crc_src[15]}] -to [get_regs {fb_writer/crc_src[0] fb_writer/crc_src[1] fb_writer/crc_src[2] fb_writer/crc_src[3] fb_writer/crc_src[4] fb_writer/crc_src[5] fb_writer/crc_src[6] fb_writer/crc_src[7] fb_writer/crc_src[8] fb_writer/crc_src[9] fb_writer/crc_src[10] fb_writer/crc_src[11] fb_writer/crc_src[12] fb_writer/crc_src[13] fb_writer/crc_src[14] fb_writer/crc_src[15]}] 2
set_multicycle_path -hold -end -from [get_regs {fb_writer/crc_src[0] fb_writer/crc_src[1] fb_writer/crc_src[2] fb_writer/crc_src[3] fb_writer/crc_src[4] fb_writer/crc_src[5] fb_writer/crc_src[6] fb_writer/crc_src[7] fb_writer/crc_src[8] fb_writer/crc_src[9] fb_writer/crc_src[10] fb_writer/crc_src[11] fb_writer/crc_src[12] fb_writer/crc_src[13] fb_writer/crc_src[14] fb_writer/crc_src[15]}] -to [get_regs {fb_writer/crc_src[0] fb_writer/crc_src[1] fb_writer/crc_src[2] fb_writer/crc_src[3] fb_writer/crc_src[4] fb_writer/crc_src[5] fb_writer/crc_src[6] fb_writer/crc_src[7] fb_writer/crc_src[8] fb_writer/crc_src[9] fb_writer/crc_src[10] fb_writer/crc_src[11] fb_writer/crc_src[12] fb_writer/crc_src[13] fb_writer/crc_src[14] fb_writer/crc_src[15]}] 1
