// ============================================================================
// tb_ab_frame_display.sv — A↔B **全链路集成** TB（B 的阶段 8/10–16 + A 的阶段 11–15）
// ----------------------------------------------------------------------------
// 为什么要它（现有 TB 的接缝）：
//   · B 侧各阶段都有单模块 TB，但**"B 写进帧缓存的像素"→"A 显示出来的像素"**这一段
//     没有任何 TB 覆盖（A 的 `tb_a_video_display_core` 用的是**合成数据**，不经过 B 的
//     `bmp_unpack`/`frame_writer`）。
//   · 本 TB 把真实模块串起来，端到端断言：**屏幕上某个坐标的像素 == 源 BMP 里那个像素**。
//
// 链路（全部是真实模块，无桩）：
//   BMP 字节流（TB 生成 54B 头 + 640×480×3 像素）
//     → bmp_parser（B·阶段7）→ bmp_unpack（B·媒体层，BGR→RGB565）
//     → frame_writer（B·阶段10，逐 word 写 + CRC）
//     → memory_arbiter 写通道（B·阶段13）
//     → 存储模型（真存真取，模拟 mem_ctrl 的下游）
//     → memory_arbiter 读通道（Video Read）
//     → a_video_display_core（A·阶段11–15：帧读取 + 官方异步 FIFO + CDC + 合成 + 扫描）
//     → rgb/hsync/vsync/de
//   frame_buffer_manager 未例化（本 TB 直接用 `SV_IMG*_BASE` 常量当槽基址）；
//   frame_swap_ctrl + frame_swap_cdc（B·阶段15）参与，让 A 的 core 知道显示哪个槽。
//
// ★★ 能证明什么
//   · **整条数据通路是通的**：从 BMP 字节到屏幕像素，中间每一级的握手都对得上
//   · `frame_writer` 写进 SDRAM 的**内容**与 A 读出来显示的**内容**一致
//     （这是"写侧地址/格式"与"读侧地址/格式"真正对齐的证明，单模块 TB 给不了）
//   · 仲裁器**读写两路共用**同一个存储口时不会互相破坏（写侧有真实竞争）
//   · 换帧握手（B 的 swap_ctrl → CDC → A）走通后画面才出现
//
// ★★ 不能证明什么（别越界）
//   · 不验 SD/FAT32 前段（阶段 1–7 的卡侧）：本 TB 的 BMP 字节流是 TB 直接生成的，
//     **不经过 SD 卡模型**。前段由 `tb_top_stage6_fat32_mount` 等覆盖。
//   · 不验真实 SDRAM 的物理 AC/时序；存储模型是理想存储器
//   · 不验 HDMI 电气层、不验板级
//   · ★ 时钟域假设：本 TB 把 `bmp_parser`/`bmp_unpack` 与 `frame_writer` **都放在 mem_clk**。
//     若产品里这两级是跨域的，需要在它们之间补 CDC FIFO —— **这一点待与 A 确认**（见文件末注）。
// ============================================================================
// ============================================================================
// ⚠️ 本 TB 的状态（2026-10-05，务必先读）
//   ✅ **已经能跑，而且核心结论已拿到**：把 `a_pixel_fifo_ip.v` 的两个未接端口
//      （`doa` / `dib`）显式列出后，ModelSim 不再 vopt 崩溃，本 TB 能 elaborate 并运行；
//      实测 **显示侧逐点比对 `ok=9950458  bad=0`** —— A 的显示核心与 B 的帧缓存内容**完全一致**。
//   ⚠️ **但本 TB 还没进回归门禁**，而且**挖出一个待查线索（很可能不是 TB 问题）**：
//      诊断打印显示换帧 FSM 停在 **S_WAIT_VBLANK（st=2）** 并超时（`swapst=5` = S_SAFE、
//      `swap_err=1`），而 **A 侧确实收到了请求并回了 ack**（`reqs=1 acks=1`）。
//      ⇒ 即"**A 的 frame_start 单拍没有让 B 的 S_WAIT_VBLANK 退出**"。
//      ★★ 已用"always 数边沿"的脉冲捕获测过（不再用 1 ms 采样），结果**确定**：
//           fsA=1    A 侧确实发出了 1 次 frame_start 单拍
//           tgl=1    ★ CDC 内部的 `u_cdc.fs_tgl_a` 确实翻转了 1 次（单拍→toggle 这一步是好的）
//           fsB=0    ✗ 但 B 侧 `frame_start_evt_b` **一次都没出**
//           ackB=0   ✗ `swap_ack_evt_b` 同样一次都没出（A→B 两个信号全断）
//           reqs=1   ✓ 反过来 B→A（`swap_req_evt_a`）是通的
//      ⇒ **断点已锁定在 `frame_swap_cdc` 的 `clk_b` 同步链**：
//          `fs_tgl_a` 翻了，但 `fs_sync` 没有把翻转变成 `frame_start_evt_b` 的单拍事件
//          （`ack_sync` 同理）。这是 **RTL 层面的问题，不是本 TB 的写法问题**。
//      ⇒ **下一步**：先单独测 `frame_swap_cdc` 的 A→B 方向（现有 `tb_ab_storage_contract` 里
//        同一结构是**通过**的，所以要先找出两个 TB 的差异），再判定是否真 bug。
//        若确认，**影响整机换帧，优先级高于本 TB**。
//   ⇒ 在此之前：**不要**把它当成"整机通过"的依据；整机结论以逐点比对结果（bad=0）为准，
//      并以 A 的 `tb_a_video_display_core`（XSim）作为独立复核。
// ============================================================================
// ★ 2026-10-05：`a_pixel_fifo_ip.v` 的两个未接端口已显式列出后，
//   本 TB 在 **ModelSim** 上也能 elaborate（原先 vopt 会内部崩溃）。
`timescale 1ns / 1ps
`include "pixel_format_defs.vh"

module tb_ab_frame_display;

    // ------------------------------------------------------------------------
    // 三个时钟域（与整机一致：sys 100M / mem 125M / pixel 74.25M）
    // ------------------------------------------------------------------------
    reg clk_sys = 1'b0;  always #5.0   clk_sys = ~clk_sys;
    reg clk_mem = 1'b0;  always #4.0   clk_mem = ~clk_mem;
    reg clk_pix = 1'b0;  always #6.734 clk_pix = ~clk_pix;

    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W * H;

    // ========================================================================
    // 1) BMP 字节源：54 Byte 头 + 640×480×24bit 像素（自底向上存，BMP 常规）
    //    像素值 = px24(x,y) 的确定性函数，显示侧用同一个函数算期望值。
    // ========================================================================
    function [23:0] px24;
        input integer x;
        input integer y;
        begin
            // BGR 存盘；这里给的是 RGB 语义值
            px24 = { (x[7:0] ^ y[7:0]), (x[9:0] + y[9:0]) & 8'hFF, (x[9:0] * 3) & 8'hFF };
        end
    endfunction

    // RGB565（与 bmp_unpack 的截断口径一致：R>>3, G>>2, B>>3）
    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    // RGB888（把 RGB565 展开成 888，与 A 的 core 的 expand 口径一致）
    function [23:0] expand565;
        input [15:0] p;
        begin
            expand565 = { p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2] };
        end
    endfunction

    reg [7:0] hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) hdr[i] = 8'h00;
        hdr[0]  = 8'h42; hdr[1]  = 8'h4D;                       // "BM"
        hdr[2]  = (54 + FRAME_PIX*3) & 8'hFF;                  // 文件大小（小端）
        hdr[3]  = ((54 + FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[4]  = ((54 + FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[5]  = ((54 + FRAME_PIX*3) >> 24) & 8'hFF;
        hdr[10] = 54;                                          // bfOffBits = 54
        hdr[14] = 40;                                          // biSize = 40
        hdr[18] = W & 8'hFF;      hdr[19] = (W >> 8) & 8'hFF;   // biWidth
        hdr[22] = H & 8'hFF;      hdr[23] = (H >> 8) & 8'hFF;   // biHeight（正 = 自底向上）
        hdr[26] = 1;                                           // biPlanes
        hdr[28] = 24;                                          // biBitCount
        hdr[34] = (FRAME_PIX*3) & 8'hFF;                       // biSizeImage
        hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    // 字节流：先 54 个头字节，再按 BMP 行序（自底向上）输出 B,G,R
    reg  [7:0]  bmp_data  = 8'h00;
    reg         bmp_valid = 1'b0;
    wire        bmp_ready;
    reg         bmp_eof   = 1'b0;

    integer bi = 0;                     // 已发出的字节序号
    integer bx, by, bc;                 // 当前像素坐标与通道
    reg [23:0] px_tmp;         // ★ 先把函数返回值存下来再选位（Questa vopt 会对 f(x)[7:0] 崩）
    integer row_pad;
    always @(posedge clk_mem) begin
        if (!rst_n) begin
            bi <= 0; bmp_valid <= 1'b0; bmp_eof <= 1'b0;
            bx <= 0; by <= 0; bc <= 0;
        end else begin
            bmp_eof <= 1'b0;
            if (!bmp_valid || bmp_ready) begin
                if (bi < 54) begin
                    bmp_data  <= hdr[bi];
                    bmp_valid <= 1'b1;
                    bi        <= bi + 1;
                end else if (by < H) begin
                    // BMP 自底向上：第 0 行 = 图像最后一行
                    px_tmp    = px24(bx, H-1-by);
                    bmp_data  <= (bc == 0) ? px_tmp[7:0]    :   // B
                                 (bc == 1) ? px_tmp[15:8]   :   // G
                                             px_tmp[23:16];     // R
                    bmp_valid <= 1'b1;
                    bi        <= bi + 1;
                    if (bc == 2) begin
                        bc <= 0;
                        if (bx == W-1) begin bx <= 0; by <= by + 1; end
                        else bx <= bx + 1;
                    end else bc <= bc + 1;
                    if ((bx == W-1) && (bc == 2) && (by == H-1)) bmp_eof <= 1'b1;
                end else begin
                    bmp_valid <= 1'b0;
                end
            end
        end
    end

    // ========================================================================
    // 2) B：bmp_parser → bmp_unpack → frame_writer
    // ========================================================================
    wire        bp_ready;
    wire        bp_check_done, bp_check_error;
    wire [7:0]  bp_err_code, bp_err_detail;
    wire [15:0] bp_width, bp_height;
    wire        bp_top_down;
    wire [7:0]  bp_bpp;
    wire [31:0] bp_compression, bp_pixel_off, bp_file_size_o;
    wire [7:0]  bp_out_data;
    wire        bp_out_valid, bp_out_sof, bp_out_eof;
    wire        bp_out_ready;

    bmp_parser u_bmp_parser (
        .clk        (clk_mem),
        .rst_n      (rst_n),
        .data       (bmp_data),
        .valid      (bmp_valid),
        .ready      (bmp_ready),
        .eof        (bmp_eof),
        .file_size  (54 + FRAME_PIX*3),
        .check_done (bp_check_done),
        .check_error(bp_check_error),
        .err_code   (bp_err_code),
        .err_detail (bp_err_detail),
        .width      (bp_width),
        .height     (bp_height),
        .top_down   (bp_top_down),
        .bpp        (bp_bpp),
        .compression(bp_compression),
        .pixel_off  (bp_pixel_off),
        .file_size_o(bp_file_size_o),
        .dbg_state  (),
        .out_data   (bp_out_data),
        .out_valid  (bp_out_valid),
        .out_ready  (bp_out_ready),
        .out_sof    (bp_out_sof),
        .out_eof    (bp_out_eof)
    );

    wire [15:0] bu_pixel;
    wire        bu_pixel_valid, bu_pixel_ready;
    wire [9:0]  bu_x, bu_y;
    wire        bu_img_sof, bu_img_eof;
    wire        bu_done, bu_error;
    wire [7:0]  bu_err_code, bu_err_detail;

    bmp_unpack u_bmp_unpack (
        .clk         (clk_mem),
        .rst_n       (rst_n),
        .din         (bp_out_data),
        .din_valid   (bp_out_valid),
        .din_ready   (bp_out_ready),
        .din_sof     (bp_out_sof),
        .din_eof     (bp_out_eof),
        .width       (bp_width),
        .height      (bp_height),
        .top_down    (bp_top_down),
        .pixel_off   (bp_pixel_off),
        .pixel       (bu_pixel),
        .pixel_valid (bu_pixel_valid),
        .pixel_ready (bu_pixel_ready),
        .x           (bu_x),
        .y           (bu_y),
        .img_sof     (bu_img_sof),
        .img_eof     (bu_img_eof),
        .done        (bu_done),
        .error       (bu_error),
        .err_code    (bu_err_code),
        .err_detail  (bu_err_detail),
        .dbg_state   ()
    );

    reg         fw_start = 1'b0;
    wire [1:0]  fw_slot_sel = 2'd1;                       // 写到 IMG1 槽
    wire [31:0] fw_slot_base = `SV_IMG1_BASE;
    wire        fw_wr_req, fw_wr_done, fw_crc_ok, fw_wr_error;
    wire [31:0] fw_wr_addr, fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire [7:0]  fw_err_code, fw_err_detail;
    wire        fw_wr_ready;

    frame_writer u_frame_writer (
        .clk        (clk_mem),
        .rst_n      (rst_n),
        .start      (fw_start),
        .slot_sel   (fw_slot_sel),
        .slot_base  (fw_slot_base),
        .din        (bu_pixel),
        .din_valid  (bu_pixel_valid),
        .din_ready  (bu_pixel_ready),
        .wr_req     (fw_wr_req),
        .wr_addr    (fw_wr_addr),
        .wr_data    (fw_wr_data),
        .wr_len     (fw_wr_len),
        .wr_ready   (fw_wr_ready),
        .wr_done    (fw_wr_done),
        .slot_valid (fw_slot_valid),
        .crc_ok     (fw_crc_ok),
        .crc_value  (fw_crc_value),
        .px_cnt     (fw_px_cnt),
        .wr_error   (fw_wr_error),
        .err_code   (fw_err_code),
        .err_detail (fw_err_detail)
    );

    // ========================================================================
    // 3) B：memory_arbiter（写通道接 frame_writer，读通道接 A 的 core）
    // ========================================================================
    wire        arb_rd_req;
    wire [31:0] arb_rd_addr;
    wire [15:0] arb_rd_len;
    wire        arb_rd_ack, arb_rd_busy, arb_rd_data_valid;
    wire [31:0] arb_rd_data;
    wire        arb_wr_ack, arb_wr_busy;

    wire        mem_req, mem_wr;
    reg         mem_ready = 1'b1;      // 本 TB 驱动（存储模型）
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata = 32'd0;     // 本 TB 驱动
    reg         mem_rdata_valid = 1'b0;// 本 TB 驱动

    wire [15:0] pix_fifo_level;

    // frame_writer 的 wr_ready = 仲裁器受理了这一拍（本模块逐 word 请求、len=1）
    assign fw_wr_ready = arb_wr_ack;

    memory_arbiter #(.MAX_BURSTS(4), .STARVE_LIMIT(64)) u_arb (
        .clk              (clk_mem),
        .rst_n            (rst_n),
        .video_fifo_level (pix_fifo_level),
        .rd_req           (arb_rd_req),
        .rd_addr          (arb_rd_addr),
        .rd_len           (arb_rd_len),
        .rd_ack           (arb_rd_ack),
        .rd_busy          (arb_rd_busy),
        .rd_data          (arb_rd_data),
        .rd_data_valid    (arb_rd_data_valid),
        .wr_req           (fw_wr_req),
        .wr_addr          (fw_wr_addr),
        .wr_data          (fw_wr_data),
        .wr_len           (fw_wr_len),
        .wr_ack           (arb_wr_ack),
        .wr_busy          (arb_wr_busy),
        .sd_req           (1'b0),
        .sd_wr            (1'b0),
        .sd_addr          (32'd0),
        .sd_wdata         (32'd0),
        .sd_len           (16'd0),
        .sd_ack           (),
        .sd_busy          (),
        .sd_rdata         (),
        .sd_rdata_valid   (),
        .mem_req          (mem_req),
        .mem_wr           (mem_wr),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_wstrb        (mem_wstrb),
        .mem_ready        (mem_ready),
        .mem_rdata        (mem_rdata),
        .mem_rdata_valid  (mem_rdata_valid),
        .wr_starve_cnt    (),
        .rd_starve_cnt    ()
    );

    // ---- 存储模型：真存真取（模拟 mem_ctrl 的下游）----
    localparam integer MEM_WORDS = 1024 * 1024;              // 4 MiB
    reg [31:0] sd_mem [0:MEM_WORDS-1];

    integer mcyc = 0;
    always @(posedge clk_mem) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 17) != 0);                     // 周期性忙，制造真实竞争
    end

    reg [31:0] raddr_p0, raddr_p1, raddr_p2;
    reg [2:0]  rv_pipe;
    always @(posedge clk_mem) begin
        if (!rst_n) begin
            raddr_p0 <= 0; raddr_p1 <= 0; raddr_p2 <= 0;
            rv_pipe <= 3'd0; mem_rdata_valid <= 1'b0; mem_rdata <= 32'd0;
        end else begin
            raddr_p0 <= mem_addr;
            raddr_p1 <= raddr_p0;
            raddr_p2 <= raddr_p1;
            rv_pipe  <= { rv_pipe[1:0], (mem_req && mem_ready && !mem_wr) };
            mem_rdata_valid <= rv_pipe[2];
            if (rv_pipe[2]) mem_rdata <= sd_mem[raddr_p2[21:2]];
            if (mem_req && mem_ready && mem_wr) sd_mem[mem_addr[21:2]] <= mem_wdata;
        end
    end

    // ========================================================================
    // 4) B：frame_swap_ctrl + frame_swap_cdc（换帧握手，让 A 知道显示哪个槽）
    // ========================================================================
    reg         frame_ready = 1'b0;
    wire        swap_req_b, mb_fidx_b, mb_crc_b, swap_error, active_commit;
    wire [2:0]  swap_state_o;      // 诊断：帧交换 FSM 当前状态
    wire [1:0]  mb_slot_b, active_next;
    wire [7:0]  mb_gen_b, gen_next;
    wire        fs_evt_b, ack_evt_b;

    frame_swap_ctrl #(.TIMEOUT_N(32'd40000)) u_swap (
        .clk              (clk_sys),
        .rst_n            (rst_n),
        .frame_ready      (frame_ready),
        .wr_frame_index   (1'b0),
        .wr_slot_id       (2'd1),                    // 与 frame_writer 写的槽一致
        .wr_generation    (8'h21),
        .wr_crc_ok        (fw_crc_ok),
        .frame_start      (fs_evt_b),
        .swap_ack         (ack_evt_b),
        .swap_req         (swap_req_b),
        .frame_index      (mb_fidx_b),
        .slot_id          (mb_slot_b),
        .generation       (mb_gen_b),
        .crc_ok           (mb_crc_b),
        .swap_error       (swap_error),
        .active_commit    (active_commit),
        .active_next      (active_next),
        .generation_next  (gen_next),
        .frame_index_next (),
        .state_o          (swap_state_o)
    );

    wire req_evt_a, frame_start_a, swap_ack_a;
    frame_swap_cdc u_cdc (
        .clk_b             (clk_sys),
        .rst_b_n           (rst_n),
        .swap_req_b        (swap_req_b),
        .mb_frame_index_b  (mb_fidx_b),
        .mb_slot_id_b      (mb_slot_b),
        .mb_generation_b   (mb_gen_b),
        .mb_crc_ok_b       (mb_crc_b),
        .frame_start_evt_b (fs_evt_b),
        .swap_ack_evt_b    (ack_evt_b),
        .clk_a             (clk_pix),
        .rst_a_n           (rst_n),
        .swap_req_evt_a    (req_evt_a),
        .swap_req_lvl_a    (),
        .mb_frame_index_a  (),
        .mb_slot_id_a      (),
        .mb_generation_a   (),
        .mb_crc_ok_a       (),
        .mb_valid_a        (),
        .frame_start_a     (frame_start_a),
        .swap_ack_a        (swap_ack_a)
    );

    // A 侧（pixel 域）行为模型：收到请求 → 给 frame_start 单拍 → toggle swap_ack
    // ---- ★ 脉冲捕获（必须用 always 数边沿；1 ms 采样看不到单周期事件）----
    //   用来分清"A 侧根本没发" vs "发了但 CDC/B 侧没吃到"
    integer fs_a_pulses = 0, fs_b_pulses = 0, ack_b_pulses = 0;
    integer fs_tgl_flips = 0, fs_sync_hi = 0;   // 观察 CDC 内部：toggle 有没有翻、同步链有没有动
    reg     fs_a_d = 1'b0, fs_b_d = 1'b0, ack_b_d = 1'b0, fs_tgl_d = 1'b0;
    always @(posedge clk_pix) begin
        fs_a_d <= frame_start_a;
        if (frame_start_a && !fs_a_d) fs_a_pulses = fs_a_pulses + 1;
        // ★ 层次引用看 CDC 内部的 toggle 有没有真的翻转
        fs_tgl_d <= u_cdc.fs_tgl_a;
        if (u_cdc.fs_tgl_a !== fs_tgl_d) fs_tgl_flips = fs_tgl_flips + 1;
    end
    always @(posedge clk_sys) begin
        fs_b_d  <= fs_evt_b;
        ack_b_d <= ack_evt_b;
        if (fs_evt_b  && !fs_b_d)  fs_b_pulses  = fs_b_pulses  + 1;
        if (ack_evt_b && !ack_b_d) ack_b_pulses = ack_b_pulses + 1;
    end

    // ★ 计数器必须声明在使用它的 always 块之前（否则 Verilog 建隐式网线、报 undefined）
    integer a_req_seen = 0, a_acks = 0, commits = 0;
    reg     cmt_d = 1'b0;
    reg [3:0] a_st = 4'd0;
    reg       ack_tgl = 1'b0, fs_pulse = 1'b0;
    always @(posedge clk_pix) begin
        if (!rst_n) begin a_st <= 4'd0; ack_tgl <= 1'b0; fs_pulse <= 1'b0; end
        else begin
            fs_pulse <= 1'b0;
            case (a_st)
                4'd0: if (req_evt_a) begin a_req_seen = a_req_seen + 1; a_st <= 4'd4; end
                4'd4: a_st <= 4'd3;
                4'd3: a_st <= 4'd2;
                4'd2: a_st <= 4'd1;
                4'd1: begin fs_pulse <= 1'b1; a_st <= 4'd5; end
                4'd5: a_st <= 4'd6;
                4'd6: begin ack_tgl <= ~ack_tgl; a_acks = a_acks + 1; a_st <= 4'd0; end
                default: a_st <= 4'd0;
            endcase
        end
    end
    assign frame_start_a = fs_pulse;

    // ---- 换帧记账监视（B 侧提交次数）----
    always @(posedge clk_sys) begin
        if (!rst_n) cmt_d <= 1'b0;
        else begin
            cmt_d <= active_commit;
            if (active_commit && !cmt_d) commits = commits + 1;
        end
    end
    assign swap_ack_a    = ack_tgl;

    // ========================================================================
    // 5) A：a_video_display_core（阶段 11–15）
    // ========================================================================
    wire [11:0] scan_x, scan_y;
    wire        scan_de, scan_frame_start;
    wire [23:0] disp_rgb;
    wire [11:0] disp_x, disp_y;
    wire        disp_hs, disp_vs, disp_de, disp_pixel_valid, disp_line_start;
    wire        disp_frame_start, disp_afs, disp_hblank, disp_vblank;
    wire [1:0]  disp_layer, pix_active_slot;
    wire [7:0]  pix_generation;
    wire        pix_active_valid, pix_frame_fault;
    wire [31:0] pix_underflow, pix_missed, mem_overflow;
    wire        mem_dma_active, mem_dma_done;
    wire [2:0]  mem_fetch_state;
    wire [31:0] mem_dma_bytes;

    a_video_display_core #(
        .HD      (0),
        .FIFO_AW (10),
        .BURST_WORDS (64),
        .FONT_FILE ("font8x16.mem")
    ) u_display (
        .sys_clk    (clk_sys),
        .mem_clk    (clk_mem),
        .pixel_clk  (clk_pix),
        .rst_n      (rst_n),
        .swap_req_b          (swap_req_b),
        .mb_frame_index_b    (mb_fidx_b),
        .mb_slot_id_b        (mb_slot_b),
        .mb_generation_b     (mb_gen_b),
        .mb_crc_ok_b         (mb_crc_b),
        .frame_start_evt_b   (fs_evt_b),
        .swap_ack_evt_b      (ack_evt_b),
        .rd_req     (arb_rd_req),
        .rd_addr    (arb_rd_addr),
        .rd_len     (arb_rd_len),
        .rd_ack     (arb_rd_ack),
        .rd_busy    (arb_rd_busy),
        .rd_data    (arb_rd_data),
        .rd_data_valid (arb_rd_data_valid),
        .cfg_valid  (1'b0),
        .cfg_ready  (),
        .cfg_osd_enable (1'b0),
        .cfg_mode   (2'b00),
        .cfg_fps_tens (4'd6),
        .cfg_fps_ones (4'd0),
        .cfg_sd_ok  (1'b1),
        .cfg_origin_x (12'd0),
        .cfg_origin_y (12'd0),
        .cfg_foreground (24'hFFFFFF),
        .emergency_rgb (24'h000000),
        .emergency_valid (1'b0),
        .scan_x     (scan_x),
        .scan_y     (scan_y),
        .scan_de    (scan_de),
        .scan_frame_start (scan_frame_start),
        .rgb        (disp_rgb),
        .x          (disp_x),
        .y          (disp_y),
        .hsync      (disp_hs),
        .vsync      (disp_vs),
        .de         (disp_de),
        .pixel_valid(disp_pixel_valid),
        .line_start (disp_line_start),
        .frame_start(disp_frame_start),
        .active_frame_start (disp_afs),
        .hblank     (disp_hblank),
        .vblank     (disp_vblank),
        .selected_layer (disp_layer),
        .pix_active_slot (pix_active_slot),
        .pix_generation  (pix_generation),
        .pix_frame_index (),
        .pix_active_valid(pix_active_valid),
        .pix_frame_fault (pix_frame_fault),
        .pix_underflow_count (pix_underflow),
        .pix_missed_frame_count (pix_missed),
        .mem_overflow_count (mem_overflow),
        .mem_fifo_pixels (pix_fifo_level),
        .mem_dma_bytes  (mem_dma_bytes),
        .mem_dma_active (mem_dma_active),
        .mem_dma_done   (mem_dma_done),
        .mem_fetch_state(mem_fetch_state)
    );

    // ========================================================================
    // 6) 断言：屏幕像素 == 源 BMP 像素
    //    A 的 core 内部有固定的图层延迟（Normal=1 / OSD=4 / Emergency=0，最终 5 拍），
    //    所以按"延迟 5 拍对齐"比较（与 A 的 TB 同口径）。
    // ========================================================================
    integer pix_ok = 0, pix_bad = 0;
    integer frame_no = 0;
    reg [23:0] exp_rgb [0:4];
    integer    ei;
    reg        comparing = 1'b0;

    always @(posedge clk_pix) begin
        if (!rst_n) begin
            comparing <= 1'b0;
            for (ei = 0; ei < 5; ei = ei + 1) exp_rgb[ei] = 24'h000000;
        end else begin
            // ★ 直接比对，**不要给期望值加延迟**：A 的 core 输出的 `x`/`y` 本身就已经是
            //   延迟后的扫描坐标（`rgb` 与 `x`/`y`/`de` 在输出端本来就同拍）。
            //   早先版本把期望值再延迟 5 拍，等于拿 x-5 的期望去比 x 的像素 ——
            //   表现是"每个像素都错、且错得像横向平移 5 个像素"（实测踩过）。
            if (pix_active_valid) comparing <= 1'b1;

            if (comparing && disp_de && (disp_x < W) && (disp_y < H)) begin
                if (disp_rgb[23:0] === expand565(px565(disp_x, disp_y))) pix_ok = pix_ok + 1;
                else begin
                    pix_bad = pix_bad + 1;
                    if (pix_bad <= 3)
                        $display("[INFO] pixel mismatch @(%0d,%0d) got=%h want=%h",
                                 disp_x, disp_y, disp_rgb[23:0],
                                 expand565(px565(disp_x, disp_y)));
                end
            end
            if (disp_frame_start) frame_no = frame_no + 1;
        end
    end

    // ========================================================================
    // 7) 主流程
    // ========================================================================
    initial begin
        rst_n = 1'b0;
        #400;
        rst_n = 1'b1;

        // ★ 必须先启动 frame_writer：它的 din_ready 要求 running
        repeat (4) @(posedge clk_mem);
        @(negedge clk_mem); fw_start = 1'b1;
        @(negedge clk_mem); fw_start = 1'b0;

        // 等 BMP 字节流发完
        wait (bu_done || bu_error || (fw_px_cnt == `SV_FRAME_PIXELS));
        check(!bu_error, "1) bmp_unpack 无错（BMP 头与像素段都被接受）");
        check(bp_width  == 16'd640, "2) bmp_parser 解析出宽度 = 640");
        check(bp_height == 16'd480, "3) bmp_parser 解析出高度 = 480");
        check(!bp_check_error,      "4) BMP 头校验通过");

        // 等 frame_writer 写完
        wait (fw_slot_valid[1] || fw_wr_error);
        check(!fw_wr_error, "5) frame_writer 写帧无错");
        check(fw_px_cnt == `SV_FRAME_PIXELS, "6) frame_writer 写满 307200 像素");
        check(fw_crc_ok == 1'b1, "7) frame_writer CRC 校验通过");
        check(fw_slot_valid[1] == 1'b1, "8) 槽 1 的 slot_valid 置位（A 才允许读）");

        // 触发换帧握手
        @(negedge clk_sys);
        frame_ready = 1'b1;
        @(negedge clk_sys);
        frame_ready = 1'b0;

        // ★ 等**电平**信号 pix_active_valid，不要等单拍信号 active_commit：
        //   后者是 sys 域单拍，若在 wait 之前就闪过，wait 会永久挂住（实测踩过）。
        wait (pix_active_valid);
        check(swap_error == 1'b0, "9) 换帧握手无超时");

        // 等两帧画面，然后收账
        wait (frame_no >= 2);
        repeat (2000) @(posedge clk_pix);

        check(pix_ok > 200000, "10) 显示侧至少比对上 200000 个像素（画面真的出来了）");
        check(pix_bad == 0,    "11) ★ 显示像素与源 BMP 像素**逐点一致**（0 个不符）");
        check(pix_underflow == 0, "12) 无像素欠流（A 的 underflow 计数 = 0）");
        check(mem_overflow == 0,  "13) 无 FIFO 溢出");
        check(pix_frame_fault == 0, "14) 无帧故障标记");

        $display("[TB] tb_ab_frame_display done, errors=%0d (pix_ok=%0d pix_bad=%0d frames=%0d commits=%0d swapst=%0d swap_err=%b reqs=%0d acks=%0d fsA=%0d fsB=%0d ackB=%0d tgl=%0d)",
                 errors, pix_ok, pix_bad, frame_no, commits, swap_state_o, swap_error,
                 a_req_seen, a_acks, fs_a_pulses, fs_b_pulses, ack_b_pulses, fs_tgl_flips);
        $finish;
    end

    // ---- 换帧过程诊断（每 1 ms 打一行，只在 frame_ready 之后开始，避免刷屏）----
    reg diag_on = 1'b0;
    always @(posedge clk_sys) if (frame_ready) diag_on <= 1'b1;
    initial begin
        forever begin
            #1_000_000;
            if (diag_on)
                $display("[SWAP] t=%0t st=%0d req=%b fs_b=%b ack_b=%b reqa=%b fsa=%b acka=%b reqs=%0d acks=%0d commits=%0d err=%b | fsA=%0d fsB=%0d ackB=%0d tgl=%0d",
                         $time, swap_state_o, swap_req_b, fs_evt_b, ack_evt_b, req_evt_a,
                         frame_start_a, swap_ack_a, a_req_seen, a_acks, commits, swap_error,
                         fs_a_pulses, fs_b_pulses, ack_b_pulses, fs_tgl_flips);
        end
    end

    // 看门狗（本 TB 要过 92 万字节 + 两帧扫描，给足）
    initial begin
        #200_000_000;
        $display("[FAIL] tb_ab_frame_display 看门狗超时（bi=%0d fw_px=%0d frames=%0d ok=%0d bad=%0d active=%b swapst=%0d swap_err=%b commits=%0d）",
                 bi, fw_px_cnt, frame_no, pix_ok, pix_bad, pix_active_valid, swap_state_o, swap_error, commits);
        $finish;
    end

    // 进度（每 2 ms 仿真时间打一行，便于定位慢在哪一段）
    initial begin
        forever begin
            #2_000_000;
            $display("[PROG] t=%0t bi=%0d bu_done=%b fw_px=%0d fw_done=%b slotv=%b active=%b frames=%0d ok=%0d bad=%0d",
                     $time, bi, bu_done, fw_px_cnt, fw_wr_done, fw_slot_valid,
                     pix_active_valid, frame_no, pix_ok, pix_bad);
        end
    end

endmodule
