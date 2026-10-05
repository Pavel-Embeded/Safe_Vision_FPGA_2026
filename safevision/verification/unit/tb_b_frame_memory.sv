// ============================================================================
// tb_b_frame_memory.sv — B 链**帧缓存内容**集成 TB（阶段 8 + 10 + 11 + 13，ModelSim 可跑）
// ----------------------------------------------------------------------------
// 为什么要它（现有 TB 的接缝）：
//   各阶段都有单模块 TB，但**"BMP 文件字节 → 帧缓存里那 153600 个 word 的内容"**
//   这一段没人端到端验过：`bmp_unpack` 的 TB 只看像素流，`frame_writer` 的 TB 用**合成图案**
//   而不是真 BMP。而这一段的产物（帧缓存里的像素布局）正是 **A 的显示核心要读的东西**。
//
// 链路（全部真实模块，无桩）：
//   BMP 字节流（TB 生成：54B 头 + 640×480×24bit，自底向上）
//     → bmp_parser（B·阶段7）→ bmp_unpack（B·媒体层，BGR→RGB565，含自底向上翻转）
//     → frame_writer（B·阶段10，2 像素/word 打包 + CRC）
//     → memory_arbiter 写通道（B·阶段13）
//     → 存储模型（真存真取）
//     → memory_arbiter **读通道**（A 的显示核心就是从这个口读的）
//     → TB 按 A 的读协议读回，**逐字与期望像素对比对**
//
// ★★ 能证明什么
//   · **从 BMP 字节到帧缓存内容，整条路是通的**（握手、字节序、行序、翻转全对）
//   · **帧缓存里的 word 布局就是 A 要读的布局**：`word k = {pix(2k+1), pix(2k)}`，
//     低半 = 先到像素（与 `frame_writer` 头注一致），**逐字 0 错**
//   · 仲裁器**读写两路**共存不互相破坏（写侧真实竞争）
//   · 读通道握手符合 A 的契约：`rd_ack` 单拍、`rd_data_valid` 只出现在 `rd_busy` 期间
//
// ★★ 不能证明什么（别越界）
//   · **不验 A 的显示核心**：A 的 `a_pixel_fifo_ip.v` 在 ModelSim 的 **vopt 阶段会让优化器
//     内部崩溃**（`ram_inst` 端口连接不全，`-novopt` 也不行）⇒ A 侧只能在他机器的 XSim 上跑。
//     全链路（含 A）的 TB 已写好并暂存为 `tb_ab_frame_display.sv.xsim_handover`，**未运行**。
//   · 不验 SD/FAT32 前段（阶段 1–7 的卡侧）：BMP 字节流是 TB 直接生成的，不经过 SD 卡模型
//   · 不验真实 SDRAM 的物理 AC/时序；存储模型是理想存储器
//   · ★ 时钟域假设：本 TB 把 `bmp_parser`/`bmp_unpack` 与 `frame_writer` **都放在 mem_clk**。
//     若产品里这两级跨域，需要补 CDC FIFO —— **待与 A 确认**（见文件末注）。
// ============================================================================
`timescale 1ns / 1ps
`include "pixel_format_defs.vh"

module tb_b_frame_memory;

    // B 的这条链统一用 mem_clk（125 MHz）
    reg clk = 1'b0;
    always #4.0 clk = ~clk;
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
    localparam integer FRAME_PIX = W * H;          // 307200
    localparam integer WORDS_TOTAL = FRAME_PIX/2;  // 153600

    // ========================================================================
    // 1) BMP 字节源
    // ========================================================================
    function [23:0] px24;
        input integer x;
        input integer y;
        begin
            px24 = { (x[7:0] ^ y[7:0]), (x[9:0] + y[9:0]) & 8'hFF, (x[9:0] * 3) & 8'hFF };
        end
    endfunction

    // RGB565：与 bmp_unpack 的截断口径一致（R>>3, G>>2, B>>3）
    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    // ★ 期望帧：在生成 BMP 字节流时**顺便填**，避免在 TB 里出现 `/` 和 `%`
    //   （Questa 10.7 的表达式代码生成对"非 2 的幂的除/模"会内部崩溃 vgenexpr.c，
    //     本 TB 早先版本就栽在这里；用"跑动计数器 + 移位"代替）。
    //   word k 的**低半 = 先到像素 = 帧内第 2k 个像素**，高半 = 第 2k+1 个（与 frame_writer 头注一致）。
    //   ★ 拆成两个 16bit 数组而不是"32bit 数组 + 部分赋值"：后者是 Questa 代码生成的雷。
    reg [15:0] exp_lo [0:WORDS_TOTAL-1];
    reg [15:0] exp_hi [0:WORDS_TOTAL-1];

    // 帧内第 n 个像素（raster 序）的 RGB565 —— n 用**递增计数**给，不做除法
    // （BMP 是自底向上存的，所以生成到 (bx,by) 时它对应帧内第 (H-1-by)*W+bx 个像素）

    reg [7:0] hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) hdr[i] = 8'h00;
        hdr[0]  = 8'h42; hdr[1]  = 8'h4D;
        hdr[2]  = (54 + FRAME_PIX*3) & 8'hFF;
        hdr[3]  = ((54 + FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[4]  = ((54 + FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[5]  = ((54 + FRAME_PIX*3) >> 24) & 8'hFF;
        hdr[10] = 54;
        hdr[14] = 40;
        hdr[18] = W & 8'hFF;      hdr[19] = (W >> 8) & 8'hFF;
        hdr[22] = H & 8'hFF;      hdr[23] = (H >> 8) & 8'hFF;
        hdr[26] = 1;
        hdr[28] = 24;
        hdr[34] = (FRAME_PIX*3) & 8'hFF;
        hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    reg  [7:0]  bmp_data  = 8'h00;
    reg         bmp_valid = 1'b0;
    wire        bmp_ready;
    reg         bmp_eof   = 1'b0;

    integer bi = 0;
    integer bx = 0, by = 0, bc = 0;
    integer fidx;              // 该 BMP 像素对应的帧内像素序号（raster）
    reg [23:0] px_tmp;         // ★ 必须先把函数返回值存进临时变量，再选位 —— 见文件末注

    always @(posedge clk) begin
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
                    // ★ 不要写 `px24(bx,H-1-by)[7:0]`：Questa 10.7 的 vopt 会对
                    //   "对函数返回值做位选" 内部崩溃（vgenexpr.c），必须先存临时变量。
                    px_tmp    = px24(bx, H - 1 - by);
                    bmp_data  <= (bc == 0) ? px_tmp[7:0]  :
                                 (bc == 1) ? px_tmp[15:8] :
                                             px_tmp[23:16];
                    bmp_valid <= 1'b1;
                    bi        <= bi + 1;
                    // 发到 R（bc==2）时这个像素就完整了 ⇒ 记进期望帧
                    if (bc == 2) begin
                        fidx = (H - 1 - by) * W + bx;
                        if (fidx[0] == 1'b0) exp_lo[fidx >> 1] <= px565(bx, H-1-by);
                        else                 exp_hi[fidx >> 1] <= px565(bx, H-1-by);
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
    // 2) bmp_parser → bmp_unpack → frame_writer
    // ========================================================================
    wire        bp_ready;
    wire        bp_check_done, bp_check_error;
    wire [7:0]  bp_err_code, bp_err_detail;
    wire [15:0] bp_width, bp_height;
    wire        bp_top_down;
    wire [7:0]  bp_bpp;
    wire [31:0] bp_compression, bp_pixel_off, bp_file_size_o;
    wire [7:0]  bp_out_data;
    wire        bp_out_valid, bp_out_sof, bp_out_eof, bp_out_ready;

    bmp_parser u_bmp_parser (
        .clk(clk), .rst_n(rst_n),
        .data(bmp_data), .valid(bmp_valid), .ready(bmp_ready), .eof(bmp_eof),
        .file_size(54 + FRAME_PIX*3),
        .check_done(bp_check_done), .check_error(bp_check_error),
        .err_code(bp_err_code), .err_detail(bp_err_detail),
        .width(bp_width), .height(bp_height), .top_down(bp_top_down),
        .bpp(bp_bpp), .compression(bp_compression), .pixel_off(bp_pixel_off),
        .file_size_o(bp_file_size_o), .dbg_state(),
        .out_data(bp_out_data), .out_valid(bp_out_valid), .out_ready(bp_out_ready),
        .out_sof(bp_out_sof), .out_eof(bp_out_eof)
    );

    wire [15:0] bu_pixel;
    wire        bu_pixel_valid, bu_pixel_ready;
    wire [9:0]  bu_x, bu_y;
    wire        bu_img_sof, bu_img_eof, bu_done, bu_error;
    wire [7:0]  bu_err_code, bu_err_detail;

    bmp_unpack u_bmp_unpack (
        .clk(clk), .rst_n(rst_n),
        .din(bp_out_data), .din_valid(bp_out_valid), .din_ready(bp_out_ready),
        .din_sof(bp_out_sof), .din_eof(bp_out_eof),
        .width(bp_width), .height(bp_height), .top_down(bp_top_down), .pixel_off(bp_pixel_off),
        .pixel(bu_pixel), .pixel_valid(bu_pixel_valid), .pixel_ready(bu_pixel_ready),
        .x(bu_x), .y(bu_y), .img_sof(bu_img_sof), .img_eof(bu_img_eof),
        .done(bu_done), .error(bu_error), .err_code(bu_err_code), .err_detail(bu_err_detail),
        .dbg_state()
    );

    reg         fw_start = 1'b0;
    wire        fw_wr_req, fw_wr_done, fw_crc_ok, fw_wr_error, fw_wr_ready;
    wire [31:0] fw_wr_addr, fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire [7:0]  fw_err_code, fw_err_detail;

    frame_writer u_frame_writer (
        .clk(clk), .rst_n(rst_n),
        .start(fw_start), .slot_sel(2'd1), .slot_base(`SV_IMG1_BASE),
        .din(bu_pixel), .din_valid(bu_pixel_valid), .din_ready(bu_pixel_ready),
        .wr_req(fw_wr_req), .wr_addr(fw_wr_addr), .wr_data(fw_wr_data), .wr_len(fw_wr_len),
        .wr_ready(fw_wr_ready), .wr_done(fw_wr_done),
        .slot_valid(fw_slot_valid), .crc_ok(fw_crc_ok), .crc_value(fw_crc_value),
        .px_cnt(fw_px_cnt), .wr_error(fw_wr_error),
        .err_code(fw_err_code), .err_detail(fw_err_detail)
    );

    // ========================================================================
    // 3) memory_arbiter + 存储模型
    // ========================================================================
    // ★ 读通道信号必须**在 arbiter 例化之前**声明：否则 Verilog 会先按隐式 1 bit 网线建，
    //   后面再显式声明就报 `vlog-2388 already declared`（顶层里也踩过同一个坑）。
    reg         arb_rd_req = 1'b0;
    reg  [31:0] arb_rd_addr = 32'd0;
    wire [15:0] arb_rd_len = 16'd64;
    wire        arb_rd_ack, arb_rd_busy, arb_rd_data_valid;
    wire [31:0] arb_rd_data;
    wire        arb_wr_ack, arb_wr_busy;
    wire        mem_req, mem_wr;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg         mem_ready = 1'b1;
    reg  [31:0] mem_rdata = 32'd0;
    reg         mem_rdata_valid = 1'b0;

    assign fw_wr_ready = arb_wr_ack;   // frame_writer 逐 word 请求、len=1

    memory_arbiter #(.MAX_BURSTS(4), .STARVE_LIMIT(64)) u_arb (
        .clk(clk), .rst_n(rst_n), .video_fifo_level(16'd32),
        .rd_req(arb_rd_req), .rd_addr(arb_rd_addr), .rd_len(arb_rd_len),
        .rd_ack(arb_rd_ack), .rd_busy(arb_rd_busy),
        .rd_data(arb_rd_data), .rd_data_valid(arb_rd_data_valid),
        .wr_req(fw_wr_req), .wr_addr(fw_wr_addr), .wr_data(fw_wr_data), .wr_len(fw_wr_len),
        .wr_ack(arb_wr_ack), .wr_busy(arb_wr_busy),
        .sd_req(1'b0), .sd_wr(1'b0), .sd_addr(32'd0), .sd_wdata(32'd0), .sd_len(16'd0),
        .sd_ack(), .sd_busy(), .sd_rdata(), .sd_rdata_valid(),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_rdata_valid(mem_rdata_valid),
        .wr_starve_cnt(), .rd_starve_cnt()
    );

    localparam integer MEM_WORDS = 512 * 1024;       // 2 MiB（槽 1 基址 0x0A0000 + 640KiB 跨度足够）
    reg [31:0] sd_mem [0:MEM_WORDS-1];

    integer mcyc = 0;
    always @(posedge clk) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 17) != 0);             // 周期性忙，制造真实竞争
    end

    reg [31:0] raddr_p0, raddr_p1, raddr_p2;
    reg [2:0]  rv_pipe;
    always @(posedge clk) begin
        if (!rst_n) begin
            raddr_p0 <= 0; raddr_p1 <= 0; raddr_p2 <= 0;
            rv_pipe <= 3'd0; mem_rdata_valid <= 1'b0; mem_rdata <= 32'd0;
        end else begin
            raddr_p0 <= mem_addr;
            raddr_p1 <= raddr_p0;
            raddr_p2 <= raddr_p1;
            rv_pipe  <= { rv_pipe[1:0], (mem_req && mem_ready && !mem_wr) };
            mem_rdata_valid <= rv_pipe[2];
            if (rv_pipe[2]) mem_rdata <= sd_mem[raddr_p2[20:2]];
            if (mem_req && mem_ready && mem_wr) sd_mem[mem_addr[20:2]] <= mem_wdata;
        end
    end

    // ========================================================================
    // 4) 读回：严格按 A 的读契约（rd_req/rd_addr/rd_len=64 → ack/busy/data_valid）
    // ========================================================================
    // 读通道驱动/监视（信号已在 §3 之前声明）
    localparam integer RD_BURST = 64;
    localparam integer N_BURST  = WORDS_TOTAL / RD_BURST;   // 2400

    reg         rd_start = 1'b0;
    integer     bst = 0;
    integer     wcnt = 0;
    integer     widx = 0;      // 帧内 word 游标（0..WORDS_TOTAL-1），不做除法
    integer     wok = 0, wbad = 0;
    integer     ack_multi = 0, v_wo_busy = 0, ack_cnt = 0, v_cnt = 0;
    reg         ack_d = 1'b0;

    always @(posedge clk) begin
        ack_d <= arb_rd_ack;
        if (!rst_n) begin
            arb_rd_req <= 1'b0; arb_rd_addr <= 32'd0;
            bst <= 0; wcnt <= 0;
        end else begin
            // 读通道契约监视
            if (arb_rd_ack && ack_d)     ack_multi = ack_multi + 1;   // rd_ack 必须单拍
            if (arb_rd_ack)              ack_cnt   = ack_cnt + 1;
            if (arb_rd_data_valid && !arb_rd_busy) v_wo_busy = v_wo_busy + 1;
            if (arb_rd_data_valid)       v_cnt     = v_cnt + 1;

            // 逐字比对（数据到达时 widx 指向帧内第几个 word —— 用跑动计数器，不做除法）
            if (arb_rd_data_valid) begin
                if (arb_rd_data === { exp_hi[widx], exp_lo[widx] }) wok = wok + 1;
                else begin
                    wbad = wbad + 1;
                    if (wbad <= 3)
                        $display("[INFO] word mismatch: burst=%0d idx=%0d got=%h want=%h",
                                 bst-1, widx, arb_rd_data, { exp_hi[widx], exp_lo[widx] });
                end
                widx = widx + 1;
                wcnt = wcnt + 1;
                if (wcnt == RD_BURST) wcnt = 0;
            end

            // 读驱动
            if (!rd_start) begin
                arb_rd_req <= 1'b0;
            end else if (bst < N_BURST) begin
                if (!arb_rd_req && !arb_rd_busy) begin
                    arb_rd_req  <= 1'b1;
                    arb_rd_addr <= `SV_IMG1_BASE + bst * RD_BURST * 4;   // 字节地址
                end else if (arb_rd_ack) begin
                    arb_rd_req <= 1'b0;
                    bst <= bst + 1;
                end
            end else begin
                arb_rd_req <= 1'b0;
            end
        end
    end

    // ========================================================================
    // 5) 主流程
    // ========================================================================
    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        // ★ 必须先启动 frame_writer：它的 `din_ready` 要求 `running`
        //   （忘了这一拍 ⇒ bmp_unpack 被挡住 ⇒ 整条链在第 59 个字节卡死，实测踩过）
        repeat (4) @(posedge clk);
        @(negedge clk); fw_start = 1'b1;
        @(negedge clk); fw_start = 1'b0;

        // 等 BMP 走完（★ 用"像素写满"当完成判据：`bmp_unpack.done` 是单拍且与
        //   `frame_writer` 的 `wr_done` 相互依赖，实测等它会把 TB 卡住；
        //   而 `fw_px_cnt` 是电平、写满 307200 就说明整条链确实走完了）
        wait (bu_done || bu_error || (fw_px_cnt == `SV_FRAME_PIXELS));
        check(!bu_error,                 "1) bmp_unpack 无错（BMP 头与像素段都被接受）");
        check(!bp_check_error,           "2) BMP 头校验通过");
        check(bp_width  == 16'd640,      "3) 解析出宽度 = 640");
        check(bp_height == 16'd480,      "4) 解析出高度 = 480");

        // 等帧写完（`slot_valid` 是电平：置位即表示整帧 + CRC 都过了）
        wait (fw_slot_valid[1] || fw_wr_error);
        check(!fw_wr_error,                    "5) frame_writer 写帧无错");
        check(fw_px_cnt == `SV_FRAME_PIXELS,   "6) frame_writer 写满 307200 像素");
        check(fw_crc_ok == 1'b1,               "7) frame_writer CRC 校验通过");
        check(fw_slot_valid[1] == 1'b1,        "8) 槽 1 slot_valid 置位（A 才允许读）");

        // 读回整帧并逐字比对
        rd_start = 1'b1;
        wait (bst >= N_BURST);
        wait (v_cnt >= WORDS_TOTAL);
        repeat (100) @(posedge clk);
        rd_start = 1'b0;

        check(wbad == 0,                 "9) ★ 帧缓存 153600 个 word **逐字与 BMP 像素对一致**（0 错）");
        check(wok  == WORDS_TOTAL,       "10) 比对字数 = 153600（不多不少）");
        check(ack_cnt == N_BURST,        "11) 读突发数 = 2400（每个突发一次 ack）");
        check(ack_multi == 0,            "12) rd_ack 单拍（无连续两拍）");
        check(v_wo_busy == 0,            "13) rd_data_valid 只在 rd_busy 期间出现");
        check(v_cnt == WORDS_TOTAL,      "14) 读回字数 = 153600");

        $display("[TB] tb_b_frame_memory done, errors=%0d (wok=%0d wbad=%0d bursts=%0d vcnt=%0d)",
                 errors, wok, wbad, ack_cnt, v_cnt);
        $finish;
    end

    // 进度
    initial begin
        forever begin
            #2_000_000;
            $display("[PROG] t=%0t bi=%0d bu_done=%b fw_px=%0d fw_done=%b slotv=%b bst=%0d vcnt=%0d wok=%0d wbad=%0d",
                     $time, bi, bu_done, fw_px_cnt, fw_wr_done, fw_slot_valid, bst, v_cnt, wok, wbad);
        end
    end

    // 看门狗
    initial begin
        #200_000_000;
        $display("[FAIL] tb_b_frame_memory 看门狗超时（bi=%0d fw_px=%0d bst=%0d vcnt=%0d wok=%0d wbad=%0d）",
                 bi, fw_px_cnt, bst, v_cnt, wok, wbad);
        $finish;
    end

endmodule
