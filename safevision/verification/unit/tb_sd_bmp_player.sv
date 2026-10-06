// ============================================================================
// tb_sd_bmp_player.sv — 方案 A 播放链的端到端验证（真卡模型 + 真 BMP 文件）
// ----------------------------------------------------------------------------
// 方案 A 之后，这条链是**两级**的：
//
//   sd_bmp_player（50 MHz 域，本 TB 里与 sink 同频）
//     SD→FAT32→目录→索引→streamer→bmp_parser→bmp_unpack→2 像素打包成 32 位字
//       │ px_word / px_word_valid / px_word_ready
//       ▼
//   bmp_frame_sink（mem 域；内含**官方 a_pixel_fifo** + A 的 bmp_frame_write_bridge）
//       │ wr_req / wr_addr / wr_data / wr_len / wr_ready
//       ▼
//   存储模型（本 TB）—— 逐像素比对
//
// 证明什么：
//   · SD 初始化 → MBR → FAT32 BPB → 根目录遍历 → 索引（4 幅）全部在**可综合模块**
//     内跑通（不是只在测试台里搭的线）；
//   · 从卡上那 921654 字节真 BMP 一路到 sink 的逐 word 写请求，写进存储的内容与
//     "同一函数算出的期望"**逐像素全对**（含行序重映射），且**经了官方 FIFO 的
//     32→16 位宽转换**（低半字先 ⇒ 像素顺序不能乱）；
//   · 换帧请求（swap_toggle + slot + generation + crc_ok）在正确时机发出，
//     且第二幅会写进**另一个槽**（槽交替）。
//
// ★ 不能证明什么（务必别越界）：
//   · 卡模型是**合成的微型 FAT32 镜像**（1 个 FAT 扇区、32 扇区/簇、声明 2048 扇区），
//     不是真实 SD 卡；不覆盖多扇区 CMD18、不覆盖真实 SD 的电气/时序 AC；
//   · 本 TB 里 player 与 sink **同频**（同一 clk）⇒ **不覆盖真实的 50M↔125M 异步**。
//     官方 FIFO 的异步行为由既有 `tb_a_pixel_fifo`（125/74 MHz）覆盖；
//     player 内部对 mem_ready/frame_done 的两级同步、sink 内部对 frame_active/
//     top_down/slot 的两级同步，在**同频下同步器等价于纯延迟**，其 CDC 正确性
//     由板级 STA（board_cdc.sdc 的例外 + 同步器结构）保证；
//   · 这里不接 A 的 `safevision_core`，用行为存储模型代替 ⇒ 不证明仲裁带宽、
//     不证明显示链、不证明 HDMI；
//   · 不证明 TD 综合/布局布线/STA。
//
// 时钟：`clk_mem` = 125 MHz（与 sink/存储链一致）。player 的参数里 SPI 分频被显式
//       覆盖成最快档（见 DUT 例化处），真实分频推导见 sd_bmp_player.v 文件头。
// ============================================================================
`timescale 1ns/1ps
`include "pixel_format_defs.vh"

module tb_sd_bmp_player;

    // ---------------------------------------------------------------- 几何
    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W*H;                       // 307200
    localparam integer FILE_BYTES = 54 + FRAME_PIX*3;         // 921654
    localparam integer FILE_SECTORS = (FILE_BYTES + 511)/512; // 1801
    localparam integer CLK_HZ = 125_000_000;

    // 卷几何（与 tb_card_to_screen 同布局）
    localparam [31:0] VOL_BASE = 32'd16;
    localparam [7:0]  SPC      = 8'd32;
    localparam [15:0] RSVD     = 16'd1;
    localparam [7:0]  NFAT     = 8'd1;
    localparam [31:0] FATSZ    = 32'd1;
    localparam [31:0] TOTSEC   = 32'd2048;
    localparam [31:0] ROOTCLUS = 32'd2;
    localparam [31:0] FILE_CLUS = 32'd3;
    localparam integer FILE_CLUS_N = (FILE_SECTORS + 31)/32;  // 57
    localparam [31:0] FILE_CLUS_LAST = FILE_CLUS + FILE_CLUS_N - 1;  // 59
    localparam [31:0] VOL_FAT_LBA   = 32'd1;
    localparam [31:0] VOL_ROOT_LBA  = 32'd2;
    localparam [31:0] VOL_FILE0_LBA = 32'd34;

    localparam [31:0] SLOT1_WORD = `SV_IMG1_BASE >> 2;        // 163840
    localparam [31:0] SLOT0_WORD = `SV_IMG0_BASE >> 2;        // 0

    // ---------------------------------------------------------------- 期望值
    // ★ 唯一真相：写卡用它、算期望也用它
    function [23:0] px24;
        input integer x;
        input integer y;
        begin
            px24 = { (x[7:0] ^ y[7:0]), (x[9:0] + y[9:0]) & 8'hFF, (x[9:0]*3) & 8'hFF };
        end
    endfunction

    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    reg [7:0] bmp_hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) bmp_hdr[i] = 8'h00;
        bmp_hdr[0]  = 8'h42; bmp_hdr[1] = 8'h4D;                 // "BM"
        bmp_hdr[2]  = (FILE_BYTES) & 8'hFF;
        bmp_hdr[3]  = (FILE_BYTES >> 8) & 8'hFF;
        bmp_hdr[4]  = (FILE_BYTES >> 16) & 8'hFF;
        bmp_hdr[5]  = (FILE_BYTES >> 24) & 8'hFF;
        bmp_hdr[10] = 54;                                        // bfOffBits
        bmp_hdr[14] = 40;                                        // biSize
        bmp_hdr[18] = W & 8'hFF;  bmp_hdr[19] = (W >> 8) & 8'hFF;
        bmp_hdr[22] = H & 8'hFF;  bmp_hdr[23] = (H >> 8) & 8'hFF; // +480 ⇒ 自底向上
        bmp_hdr[26] = 1;                                         // biPlanes
        bmp_hdr[28] = 24;                                        // biBitCount
        bmp_hdr[34] = (FRAME_PIX*3) & 8'hFF;
        bmp_hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        bmp_hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        bmp_hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    // 卡上文件第 j 个字节（行序自底向上，通道 B,G,R）
    function [7:0] filebyte;
        input integer j;
        integer p, n, c, r, x, y;
        reg [23:0] pxv;
        begin
            if (j < 54) filebyte = bmp_hdr[j];
            else begin
                p = j - 54;
                n = p / 3;
                c = p - n*3;
                r = n / W;
                x = n - r*W;
                y = H - 1 - r;
                pxv = px24(x, y);
                filebyte = (c == 0) ? pxv[7:0] : (c == 1) ? pxv[15:8] : pxv[23:16];
            end
        end
    endfunction

    // 光栅像素 k（k = y*W + x）的期望 RGB565
    function [15:0] exp565_k;
        input integer k;
        begin
            exp565_k = px565(k % W, k / W);
        end
    endfunction

    // ---------------------------------------------------------------- 时钟/复位
    reg clk_mem = 1'b0;
    always #4 clk_mem = ~clk_mem;      // 125 MHz
    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input        cond;
        input string msg;
        begin
            if (cond) $display("[PASS] %s", msg);
            else begin $display("[FAIL] %s", msg); errors = errors + 1; end
        end
    endtask

    // ---------------------------------------------------------------- DUT 接口
    // player（50 MHz 域；本 TB 与 sink 同频）
    wire        sd_ncs, sd_dclk, sd_mosi, sd_miso;
    wire [31:0] px_word;
    wire        px_word_valid, px_word_ready;
    wire        frame_active, top_down_o;
    wire [1:0]  pl_slot;
    wire [3:0]  pl_state, pl_fail_stage;
    wire [7:0]  pl_ec, pl_ed;
    wire        pl_sd_ready, pl_card_usable;
    wire [3:0]  pl_file_cnt;
    wire [1:0]  pl_cur_file;
    wire [31:0] pl_file_size, pl_bytes_rd;
    wire [18:0] pl_px_written;
    wire        pl_last_frame_ok;
    wire [15:0] pl_frame_cnt;

    // sink（mem 域）
    wire        wr_req, wr_ready;
    wire [31:0] wr_addr, wr_data;
    wire [15:0] wr_len;
    wire        sw_toggle;
    wire [1:0]  sw_slot;
    wire [7:0]  sw_gen;
    wire        sw_crc_ok;
    reg         swap_busy;
    wire        mem_ready, frame_done, sink_last_frame_ok;
    wire [3:0]  sk_state;
    wire [7:0]  sk_ec, sk_ed;
    wire [15:0] sk_frame_cnt;
    wire [18:0] sk_px_written;

    reg run = 1'b0, btn_next = 1'b0, btn_auto = 1'b0, restart = 1'b0;

    // ---------------------------------------------------------------- 卡模型
    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;

    sd_spi_card_model #(
        .VOL_BASE    (VOL_BASE),
        .VOL_SECTORS (2048)                 // ★ 扩到 1 MiB：装得下 921654 字节的 BMP
    ) u_card (
        .sclk(sd_dclk), .cs_n(sd_ncs), .mosi(sd_mosi), .miso(sd_miso),
        .i_dead(1'b0),
        .o_cmd(o_cmd), .o_arg(o_arg), .o_acmd41_arg(o_acmd41_arg),
        .o_cmd_cnt(o_cmd_cnt), .o_acmd41_cnt(o_acmd41_cnt), .o_cmd_valid(o_cmd_valid)
    );

    // ---------------------------------------------------------------- 卷构造
    task mbr_set_card0;
        begin
            u_card.sector[450] = 8'h0C;             // FAT32 LBA (XINT13)
            u_card.sector[454] = VOL_BASE[7:0];     // 分区起始 LBA（小端）
            u_card.sector[455] = VOL_BASE[15:8];
            u_card.sector[456] = VOL_BASE[23:16];
            u_card.sector[457] = VOL_BASE[31:24];
            u_card.sector[458] = 8'h00;
            u_card.sector[459] = 8'h00;
            u_card.sector[460] = 8'h01;
            u_card.sector[461] = 8'h00;
            u_card.sector[510] = 8'h55;
            u_card.sector[511] = 8'hAA;
        end
    endtask

    task build_volume;
        integer c, s, o, j;
        begin
            u_card.mk_fat32_dbr(16'd512, SPC, RSVD, NFAT, FATSZ, ROOTCLUS, TOTSEC, 1'b1);
            // FAT：FAT[2]=EOC，FAT[3..58]=next，FAT[59]=EOC
            u_card.vol_zero(VOL_FAT_LBA);
            u_card.vol_set_le(VOL_FAT_LBA, 16'd8, 32'h0FFF_FFFF, 3'd4);
            for (c = 3; c <= FILE_CLUS_LAST - 1; c = c + 1)
                u_card.vol_set_le(VOL_FAT_LBA, c*4, c+1, 3'd4);
            u_card.vol_set_le(VOL_FAT_LBA, FILE_CLUS_LAST*4, 32'h0FFF_FFFF, 3'd4);
            // 根目录：4 条目录项
            u_card.vol_zero(VOL_ROOT_LBA);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd0,  "SV0001  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd32, "SV0002  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd64, "SV0003  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd96, "SV0004  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            // 文件主体：整幅真 BMP 写进卷（簇连续 ⇒ 文件扇区 s 在卷内 LBA = 34+s）
            for (s = 0; s < FILE_SECTORS; s = s + 1) begin
                u_card.vol_used[VOL_FILE0_LBA + s] = 1'b1;
                for (o = 0; o < 512; o = o + 1) begin
                    j = s*512 + o;
                    u_card.vol[(VOL_FILE0_LBA + s)*512 + o] = (j < FILE_BYTES) ? filebyte(j) : 8'h00;
                end
            end
            mbr_set_card0;
        end
    endtask

    // ---------------------------------------------------------------- DUT：player
    sd_bmp_player #(
        .CLK_HZ (CLK_HZ),
        // ★ 仿真提速：真实默认是 INIT=62 / FAST=0（按 50 MHz 算，符合 SD 规范），
        //   但那是给**真卡**用的；卡模型不校验 SCLK，按真实分频跑一幅要 ~590 ms
        //   仿真时间。这里取 spi_master 允许的最快档（div=0 会被钳到 1 ⇒
        //   SCLK = 125M/(2*2) = 31.25 MHz），一幅约 236 ms。
        //   ★ 分频只影响速度、不影响这条链的功能正确性；
        //   50 MHz 下真实分频的推导见 sd_bmp_player.v 文件头。
        .CLK_DIV_INIT (16'd1),
        .CLK_DIV_FAST (16'd0)
    ) dut_player (
        .clk(clk_mem), .rst_n(rst_n),
        .run(run), .btn_next(btn_next), .btn_auto(btn_auto), .restart(restart),
        .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .px_word(px_word), .px_word_valid(px_word_valid), .px_word_ready(px_word_ready),
        .frame_active(frame_active), .top_down_o(top_down_o), .slot_o(pl_slot),
        .mem_ready(mem_ready), .frame_done(frame_done), .last_frame_ok(sink_last_frame_ok),
        .state_o(pl_state), .fail_stage(pl_fail_stage),
        .err_code(pl_ec), .err_detail(pl_ed),
        // 诊断口（SD 初始化 R1/命令序号）：本 TB 用真卡模型，不需要，显式空连接
        .init_r1(), .init_seq(),
        .sd_ready(pl_sd_ready), .card_usable(pl_card_usable),
        .file_cnt(pl_file_cnt), .cur_file(pl_cur_file),
        .cur_file_size(pl_file_size), .cur_bytes_rd(pl_bytes_rd),
        .cur_px_written(pl_px_written), .last_frame_ok_o(pl_last_frame_ok),
        .frame_cnt(pl_frame_cnt)
    );

    // ---------------------------------------------------------------- DUT：sink
    //   ★ wr_clk 与 clk 同频（本 TB 同频；真实板级是 50/125 异步）
    bmp_frame_sink u_sink (
        .clk(clk_mem), .rst_n(rst_n), .wr_clk(clk_mem),
        .px_word(px_word), .px_word_valid(px_word_valid), .px_word_ready(px_word_ready),
        .frame_active(frame_active), .top_down(top_down_o), .slot(pl_slot),
        .mem_ready(mem_ready), .frame_done(frame_done), .last_frame_ok(sink_last_frame_ok),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ready(wr_ready),
        .swap_toggle(sw_toggle), .swap_slot(sw_slot), .swap_generation(sw_gen),
        .swap_crc_ok(sw_crc_ok), .swap_busy(swap_busy),
        .state_o(sk_state), .err_code(sk_ec), .err_detail(sk_ed),
        .frame_cnt(sk_frame_cnt), .px_written(sk_px_written)
    );

    // ---------------------------------------------------------------- 存储模型
    // 4 MiB word 存储；wr_ready 周期性地忙一拍，制造真实反压
    localparam integer MEM_WORDS = 1024*1024;
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [4:0]  stall = 5'd0;
    always @(posedge clk_mem) stall <= stall + 5'd1;
    assign wr_ready = (stall != 5'd31);

    always @(posedge clk_mem) begin
        if (wr_req && wr_ready) mem[wr_addr[21:2]] <= wr_data;
    end

    // ---------------------------------------------------------------- 换帧握手模拟
    // core 的 swap_state_o 会先忙再落；这里用 30 拍忙窗复现该行为
    //   ★ 触发源改成 sink 的 swap_toggle（方案 A 之后换帧请求由 sink 发出）
    reg        rt_d = 1'b0;
    reg [7:0]  swap_cnt = 8'd0;
    always @(posedge clk_mem) begin
        rt_d <= sw_toggle;
        if (sw_toggle != rt_d) swap_cnt <= 8'd30;
        else if (swap_cnt != 8'd0) swap_cnt <= swap_cnt - 8'd1;
    end
    always @(posedge clk_mem) swap_busy <= (swap_cnt != 8'd0);

    // ---------------------------------------------------------------- 比较
    integer k, n, bad, first_bad;
    reg [31:0] got, exp;
    task cmp_frame;
        input [31:0] base_word;
        input string label;
        integer nn, kk, b;
        begin
            b = 0;
            for (nn = 0; nn < FRAME_PIX/2; nn = nn + 1) begin
                kk = nn*2;
                got = mem[base_word + nn];
                exp = { exp565_k(kk+1), exp565_k(kk) };
                if (got !== exp) begin
                    if (b == 0)
                        $display("       first mismatch pair=%0d addr=0x%08x got=%08x exp=%08x",
                                 nn, (base_word+nn)<<2, got, exp);
                    b = b + 1;
                end
            end
            if (b == 0) $display("[PASS] %s : %0d words pixel-exact", label, FRAME_PIX/2);
            else begin
                $display("[FAIL] %s : %0d / %0d words differ", label, b, FRAME_PIX/2);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------- 主流程
    integer guard;
    // 一幅真 BMP 约 236 ms 仿真时间（见 DUT 例化处注释）⇒ 守卫必须远大于它
    localparam integer FRAME_GUARD = 45_000_000;   // 360 ms
    integer wd;
    initial begin
        run = 1'b0; btn_next = 1'b0; btn_auto = 1'b0; restart = 1'b0;
        repeat (10) @(posedge clk_mem);
        rst_n = 1'b1;
        repeat (5) @(posedge clk_mem);

        // 构造卡卷
        build_volume;
        $display("[TB] card volume built: 4 x SV00xx.BMP, %0d bytes each", FILE_BYTES);

        // 启动
        @(posedge clk_mem); run = 1'b1;

        // ---- 等 SD 初始化 ----
        guard = 0;
        while (!pl_sd_ready && guard < 3_000_000) begin @(posedge clk_mem); guard = guard + 1; end
        check(pl_sd_ready, "1) SD init done within window (sd_ready=1)");

        // ---- 等挂载 + 索引 ----
        guard = 0;
        while (!pl_card_usable && guard < 3_000_000) begin @(posedge clk_mem); guard = guard + 1; end
        check(pl_card_usable, "2) MBR+BPB+dir+index all done (card_usable=1)");
        check(pl_file_cnt == 4'd4, "3) indexed 4 valid BMP files");

        // ---- 等第一幅（写进 slot 1）----
        guard = 0;
        while (pl_frame_cnt < 16'd1 && guard < FRAME_GUARD) begin @(posedge clk_mem); guard = guard + 1; end
        check(pl_frame_cnt >= 16'd1, "4) frame 1 completed (frame_cnt >= 1)");
        check(pl_fail_stage == 4'd0, "5) never entered an error stage");
        check(sk_state != 4'd3, "6) sink never entered S_ERROR");
        check(sink_last_frame_ok, "7) frame 1 CRC passed (sink last_frame_ok=1)");
        check(sw_slot == 2'd1, "8) frame 1 written into slot 1");
        check(sk_px_written == 19'd307200, "9) exactly 307200 pixels written by the bridge");
        check(pl_file_size == FILE_BYTES, "10) file size = 921654 bytes");
        check(pl_bytes_rd == FILE_BYTES, "11) all 921654 bytes streamed from card");

        // 等换帧握手走完
        guard = 0;
        while (pl_state != 4'd7 && guard < 500_000) begin @(posedge clk_mem); guard = guard + 1; end
        check(pl_state == 4'd7, "12) swap completed, back to S_READY");
        check(pl_slot == 2'd0, "13) slot alternated to 0 for the next frame");
        repeat (50) @(posedge clk_mem);
        cmp_frame(SLOT1_WORD, "14) slot 1 content (frame 1)");

        // ---- 第二幅：脉冲 btn_next，应重新进入 S_STREAM 并写另一个槽 ----
        //    ★ 只验证“FSM 能干净地重入 + 槽交替”这一层（跑完整第二幅要再花
        //      ~236 ms 仿真时间，回报有限；整幅逐像素已由第一幅全覆盖）
        @(posedge clk_mem); btn_next = 1'b1;
        @(posedge clk_mem); btn_next = 1'b0;
        guard = 0;
        while (pl_state != 4'd8 && guard < 500_000) begin @(posedge clk_mem); guard = guard + 1; end
        check(pl_state == 4'd8, "15) re-entered S_STREAM for frame 2");
        check(pl_slot == 2'd0, "16) frame 2 targets slot 0 (double buffering OK)");
        check(pl_fail_stage == 4'd0, "17) still no error stage after re-entry");

        $display("============================================");
        if (errors == 0) $display("  SD-BMP-PLAYER PASS (0 error)");
        else             $display("  SD-BMP-PLAYER FAIL (%0d error)", errors);
        $display("============================================");
        $finish;
    end

    // 总看门狗：任何情况都有界退出
    initial begin
        wd = 0;
        while (wd < 70_000_000) begin @(posedge clk_mem); wd = wd + 1; end
        $display("[FAIL] global watchdog: pl_state=%0d fail_stage=%0d err=0x%02x 0x%02x sk_state=%0d sk_err=0x%02x cnt=%0d",
                 pl_state, pl_fail_stage, pl_ec, pl_ed, sk_state, sk_ec, pl_frame_cnt);
        $display("  SD-BMP-PLAYER FAIL (watchdog)");
        $finish;
    end

endmodule
