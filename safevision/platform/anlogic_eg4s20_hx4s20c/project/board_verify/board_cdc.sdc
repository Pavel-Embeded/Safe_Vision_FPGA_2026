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
# ★ 上面这条有两个实测的脆弱点（2026-10-06 都踩到）：
#   ① `-to [get_pins {*/*.sr}]` 只匹配**两级**路径名；综合出来的顶层单元是一级形式
#      （实测端点 `add5_syn_104.sr`）⇒ 静默漏掉。
#   ② `-through [get_nets {common_rst_n}]` 依赖那个 AND 网被保留成独立命名网。
#   漏掉的后果：board_clk → 像素域的异步复位脚被当成真的 recovery 检查，
#   预算只有 0.302 ns（50 MHz 与 25.185 MHz 不相关）⇒ 报 −3.94 ns 假违例。
#   ⇒ 复位纪元只在 **board_clk 域**产生（reset_ref），所以用时钟源形式兜底：
#     凡是从 board_clk 域寄存器到任何异步复位/置位脚的路径，都是复位分发路径。
set_false_path -from [get_clocks {board_clk}] -to [get_pins {*.sr}]
set_false_path -from [get_clocks {board_clk}] -to [get_pins {*/*.sr}]

# ---- mem -> sys submit toggle (frame_ready) ----
# The mem-domain write completion is published as a toggle and synchronized in
# sys_clk. Only the first synchronizer stage input is exempt.
# ★ 2026-10-06 订正：原 `set_false_path -to [get_regs {submit_sync[0]}]` 是**死约束**
#   （submit_sync 寄存器已不在 RTL 里，现行名字是下面的 tog_sync[0]）。
#   route.check 第 4 节 "checking invalid constraints" 实证报无效 ⇒ 移除。
#   这是缺陷 23（get_regs 对不存在的名字静默落空）的新病例：约束必须对着
#   route.check 验证过的名字写。

# ---- Inside safevision_core (same structure A constrained) ----
set_false_path -to [get_regs {core/display/config_mailbox/req_meta core/display/config_mailbox/ack_meta core/display/fetch/frame_request/req_meta core/display/fetch/frame_request/ack_meta core/display/fetch/arm_sync/meta core/display/swaps/req_sync[0] core/display/swaps/fs_sync[0] core/display/swaps/ack_sync[0]}]
set_false_path -from [get_clocks {video_*$video_pll/pll_inst.clkc[1]}] -to [get_pins {core/display/fetch/fetch_mem_reset/*.sr}]
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

# ---- Board-level producer handshake (bmp_frame_sink -> core) ----
# mem -> sys: the frame-ready EVENT crosses as a toggle through two stages, and
# the payload (slot/generation/crc_ok) is a bundled-data capture that is sampled
# on the cycle the event arrives. The payload holds stable for many source
# cycles, so it is bounded by max_delay rather than exempted.
set_false_path -to [get_regs {tog_sync[0]}]
# ★★ 2026-10-06 深度定责（defect 23 家族新病例）：原写法
#   `-from [get_clocks {system_pll/pll_inst.clkc[1]}]` 在 read_sdc 解析时刻**静默落空**：
#   TD 的时钟对象要到 update_timing 才实体化——read_sdc 刚执行完时 get_clocks
#   连 board_clk 都返回空（probe10 实证），而 get_regs 在解析时刻就能解析（probe11）。
#   后果：route.exceptions 里该约束历次 Total=0 ⇒ "toggle 翻转后载荷在 1 个 sys
#   周期内到达"这个换帧打包不错拍的物理前提，**一直没有被真正验证过**。
#   ★ 教训：凡 -from [get_clocks ...] 形式的约束，必须到 route.exceptions 查
#   Total>0 才算生效；route.check 的 "invalid constraint" 检查**不会**抓这种落空。
#   ⇒ 改为 -from 侧点名真实的 mem 域源寄存器（get_regs 按 Q 网名解析，可打包孪生）：
#     · sink/swap_slot*          —— 打包槽号（孪生 slot_lat[0] 自动跟随）
#     · sink/last_frame_ok*      —— 帧 CRC 结果（孪生 writer/crc_ok 跟随）
#     · sink/u_bridge/writer/crc_ok* —— writer 帧结果链
#     · fb_writer/crc_ok*        —— 回落路径载荷
#     · fb_drain*                —— 字计数（mux 锥输入）
#   别名解析（综合吸收改名）：slot_sys* → core/swap_ctrl/wr_slot_id[0]、
#   crc_sys → core/swap_ctrl/wr_crc_ok；gen_sys 整族已被综合吸收（布线网表里
#   没有 generation 网，无路径需要约束）⇒ 从 -to 里删掉 gen_sys*（留着只添告警）。
#   ⚠ 已知开放项：本文件上方几条 -from [get_clocks ...] 形式的 set_false_path
#   （复位段 38/39/41 行）有同样的解析时刻问题，行为待专门核查后一并订正。
set_max_delay -datapath_only -from [get_regs {sink/swap_slot* sink/last_frame_ok* sink/u_bridge/writer/crc_ok* fb_writer/crc_ok* fb_drain*}] -to [get_regs {slot_sys* crc_sys}] 8.000
# sys -> mem: swap-busy level, first synchronizer stage only.
# NOTE: core/swap_ctrl runs on sys_clk (see frame_swap_ctrl.v), so the sink's
# swap_busy input must be the SYNCHRONIZED swap_busy_mem, not swap_state_o.
set_false_path -to [get_regs {sb_sync[0]}]

# ---- Plan A: SD/media chain now runs on the 50 MHz board clock ----
# sd_bmp_player (board_clk, 50 MHz) <-> bmp_frame_sink (mem_clk, 125 MHz).
# The two domains meet at exactly three places, all intentional:
#
# (a) Reset. bmp_frame_sink drives the official pixel FIFO's asynchronous reset
#     from mem_rst_n. Asynchronous assertion is by design and the per-domain
#     synchronous release lives inside the IP (wr_rst_done), exactly like the
#     board-level reset epoch handled above. mem_rst_n is a reset net only.
set_false_path -from [get_nets {mem_rst_n}]
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
set_false_path -to [get_regs {t_state1* t_fail1* t_ec1* t_sd1* t_card1* t_fok1* t_fcnt1* t_cur1* t_bytes1* t_fcnt16_1*}]
#
# (d) The 32-bit pixel stream itself crosses ONLY through the official
#     a_pixel_fifo, whose internal Gray-code pointer synchronizers are bounded
#     (not exempted) exactly like the display fetch FIFO above. Its write side is
#     wr_clk = board_clk and its read side is mem_clk.
set_max_delay -datapath_only -from [get_regs {sink/u_fifo/fifo/wr_to_rd_cross_inst/primary_addr_gray_reg*}] -to [get_regs {sink/u_fifo/fifo/wr_to_rd_cross_inst/sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {sink/u_fifo/fifo/rd_to_wr_cross_inst/primary_addr_gray_reg*}] -to [get_regs {sink/u_fifo/fifo/rd_to_wr_cross_inst/sync_r1*}] 8.000

# ---- Mechanical push-buttons ----
# btn_next / btn_auto feed only a debounce counter comparison; a metastable
# sample merely delays detection, and the debounce filters it. No clock budget
# exists for a hand-operated switch, so treat them as asynchronous inputs.
set_false_path -from [get_ports {btn_next btn_auto}]

# ---- Slow board outputs with no measured I/O budget yet ----
# sd_dclk (SPI, <=20.8 MHz), sd_mosi, sd_ncs and uart_txd (115200 baud) are
# deliberately left WITHOUT output delay numbers, exactly like the bring-up top
# that already passed routed STA. Add I/O delays once measured on hardware.

# ---- UART status reporter: ridx -> report mux is a true 2-cycle path ----
# 2026-10-06, mem->mem domino #2 (after the fetch guarded_level cut). The 90-way
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
# route.timing; a silently-empty get_regs match would leave them at 8 ns
# (defect 23 lesson: TD does NOT warn on empty collections).
# ★ 2026-10-06 订正（guardfix2 的 route.check 第 4 节实证这两条被判 invalid）：
#   ① get_regs 按 **Q 端 net 名**匹配（SWUG200 §3.1.9），Q 网名是 `ridx[N]`
#      而不是 `ridx_reg*` ⇒ 正确通配是 {ridx*}；
#   ② TD 官方语法（SWUG200 p38-41）数值放**最后**：`... -from [...] 2`；
#   ③ setup N 周期时 hold 需显式补 N-1 且同侧（-end），否则 hold 仍在原边。
set_multicycle_path -setup -from [get_regs {ridx*}] 2
set_multicycle_path -hold -end -from [get_regs {ridx*}] 1
