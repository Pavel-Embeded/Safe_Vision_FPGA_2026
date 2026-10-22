// ============================================================================
// tb_framebuffer_loopback_core.sv — 阶段 10 帧缓存回环核心
// ----------------------------------------------------------------------------
// 被测：rtl/memory/framebuffer_loopback_core.v
//       + mem_ctrl / memory_arbiter / frame_writer / frame_address_gen /
//         video_read_dma / sync_fifo（全部在核心里被例化）
// 后端：verification/models/frame_memory_model.sv（顶替加密 SDRAM IP）
//
// 数据通路（mem 域单时钟 8ns=125MHz）：
//   LFSR 像素源 -> frame_writer -> memory_arbiter(写) -> mem_ctrl -> 模型
//   mem_ctrl <- memory_arbiter(读) <- video_read_dma <- 像素 FIFO <- 自检器
//
// 断言要点：
//   T1 回环通过 ok=1                T2 无错误码
//   T3 写入像素数 = 307200          T4 读回像素数 = 307200
//   T5 逐像素比对零错 (bad=0)        T6 frame_writer 抽样 CRC 通过
//   T7 slot_valid 置位              T8 报告 = 208 Byte
//   T9 报告字节逐字节正确
//   T10 地址斜坡探针：写进 SDRAM 的值 = 它自己的字地址（A 段 32 + B 段 4）
//   T11 地址斜坡探针：段内写地址严格连续，且两段基址 = 0x1000 / 0x1035
//
// ★ 报告是按"发射顺序"拼的，期望值必须用 2 位十六进制（CRC=01 / SV=01），
//   别写成 CRC=1 / SV=1（那是 1 位，对不上）。
// ★ 探针期望值（T9 里逐字节写死）：`AM=FFFFFFFF`（32 个回读全等于期望）、
//   `AF=FF`（无首个不符）、`AV=00000000`、`C0..C3`=1004/1005/1006/1007（非零偏移处
//   4 个回读 = 该处真实内容）、`B0..B3`=1035/1036/1037/1038（非 16 对齐基址）——
//   因为"写进去的值就是它的字地址"（见核心文件头）。
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_framebuffer_loopback_core;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #4 clk = ~clk;          // 8 ns -> 125 MHz

    integer errors = 0;
    integer total  = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            total = total + 1;
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // ---- 核心 <-> 后端 ----
    wire        c_req, c_wr;
    wire [31:0] c_addr, c_wdata;
    wire [3:0]  c_wstrb;
    wire [31:0] c_rdata;
    wire        c_rvalid, c_ready, c_initdone;

    // ---- 报告 / 状态 ----
    wire        rep_valid;
    wire        rep_ready;
    wire [7:0]  rep_data;
    wire        fb_ok, crc_ok, slot_valid;
    wire [7:0]  err_code;
    wire [18:0] wr_px, rd_px, bad_px;

    assign rep_ready = 1'b1;       // TB 恒可收，报告直接流出

    framebuffer_loopback_core u_core (
        .clk               (clk),
        .rst_n             (rst_n),
        .sdram_req         (c_req),
        .sdram_wr          (c_wr),
        .sdram_addr        (c_addr),
        .sdram_wdata       (c_wdata),
        .sdram_wstrb       (c_wstrb),
        .sdram_rdata       (c_rdata),
        .sdram_rdata_valid (c_rvalid),
        .sdram_ready       (c_ready),
        .sdram_init_done   (c_initdone),
        .rep_valid         (rep_valid),
        .rep_data          (rep_data),
        .rep_ready         (rep_ready),
        .ok                (fb_ok),
        .err_code          (err_code),
        .wr_px             (wr_px),
        .rd_px             (rd_px),
        .bad_px            (bad_px),
        .crc_ok            (crc_ok),
        .slot_valid        (slot_valid)
    );

    frame_memory_model u_mem (
        .clk        (clk),
        .rst_n      (rst_n),
        .req        (c_req),
        .wr         (c_wr),
        .addr       (c_addr),
        .wdata      (c_wdata),
        .wstrb      (c_wstrb),
        .rdata      (c_rdata),
        .rdata_valid(c_rvalid),
        .ready      (c_ready),
        .init_done  (c_initdone)
    );

    // ---- 报告捕获：按发射顺序左移拼成 208 Byte 向量 ----
    localparam integer RPT_LEN = 208;
    reg [8*RPT_LEN-1:0] got_vec;
    integer rep_n = 0;

    always @(posedge clk) begin
        if (rst_n && rep_valid) begin
            got_vec <= { got_vec[8*RPT_LEN-8-1:0], rep_data };
            rep_n   <= rep_n + 1;
        end
    end

    wire [8*RPT_LEN-1:0] exp_vec = {
        "SV-FB-LOOP", 8'h0D, 8'h0A,
        "INIT=01",    8'h0D, 8'h0A,
        "WR=04B000 CRC=01 SV=01", 8'h0D, 8'h0A,
        "RD=04B000 BAD=000000",   8'h0D, 8'h0A,
        "W0=59C3ACE1 W1=670FB387", 8'h0D, 8'h0A,
        "AM=FFFFFFFF", 8'h0D, 8'h0A,
        "AF=FF",       8'h0D, 8'h0A,
        "AV=00000000", 8'h0D, 8'h0A,
        "C0=1004 C1=1005 C2=1006 C3=1007", 8'h0D, 8'h0A,
        "B0=1035 B1=1036 B2=1037 B3=1038", 8'h0D, 8'h0A,
        "BF=000000", 8'h0D, 8'h0A,
        "DONE",       8'h0D, 8'h0A
    };

    // ------------------------------------------------------------------------
    // 地址斜坡探针监视（T10/T11）：在核心的 mem 事务口上"旁听"探针的写访问
    //   期望：值 == 字地址（A 段 0x1000+ / B 段 0x1035+ 都是"值 = 自己的地址"），
    //         且**段内**地址严格连续（步长 1 个 word）。
    //   ★ 只在前 36 个写访问上判（探针 A 32 个 + 探针 B 4 个），之后的整帧写入
    //     写的是 LFSR 像素值，不适用本条。
    //   ★ 注意：A 段末尾 0x101F 与 B 段首字 0x1035 **并不连续**（B 是刻意取非
    //     16 对齐的基址），所以连续性必须分两段各判一次，不能跨段累加。
    // ------------------------------------------------------------------------
    integer wacc = 0;
    reg     prb_val_bad  = 1'b0;
    reg     prb_a_bad    = 1'b0;
    reg     prb_b_bad    = 1'b0;
    reg [31:0] prb_a_first = 32'd0;
    reg [31:0] prb_b_first = 32'd0;

    always @(posedge clk) begin
        if (rst_n && c_req && c_ready && c_wr) begin
            if (wacc < 36) begin
                if (c_wdata !== c_addr) prb_val_bad <= 1'b1;      // 值 = 字地址
                if (wacc == 0)  prb_a_first <= c_addr;
                if (wacc == 32) prb_b_first <= c_addr;
                if ((wacc > 0) && (wacc < 32)) begin
                    if (c_addr !== (prb_a_first + wacc)) prb_a_bad <= 1'b1;
                end else if (wacc > 32) begin
                    if (c_addr !== (prb_b_first + (wacc - 32))) prb_b_bad <= 1'b1;
                end
            end
            wacc <= wacc + 1;
        end
    end

    integer guard;

    initial begin
        got_vec = {8*RPT_LEN{1'b0}};
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        guard = 0;
        while (!fb_ok && (err_code == 8'h00) && (guard < 20_000_000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        // 等报告发完（避免在只发了几个字节时就检查）
        guard = 0;
        while ((rep_n < RPT_LEN) && (guard < 200_000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        repeat (2) @(negedge clk);

        $display("---- 帧缓存回环结果 ----");
        $display("  wr_px=%0d rd_px=%0d bad=%0d err=%02h rep_n=%0d",
                 wr_px, rd_px, bad_px, err_code, rep_n);
        $display("  探针写访问数=%0d A首址=%08h B首址=%08h 值错=%0b A段地址错=%0b B段地址错=%0b",
                 wacc, prb_a_first, prb_b_first, prb_val_bad, prb_a_bad, prb_b_bad);

        check(fb_ok      === 1'b1,        "T1 回环通过 ok=1");
        check(err_code   === 8'h00,       "T2 无错误码");
        check(wr_px      === 19'd307200,  "T3 写入像素数 = 307200");
        check(rd_px      === 19'd307200,  "T4 读回像素数 = 307200");
        check(bad_px     === 19'd0,       "T5 逐像素比对零错");
        check(crc_ok     === 1'b1,        "T6 frame_writer 抽样 CRC 通过");
        check(slot_valid === 1'b1,        "T7 slot_valid 置位");
        check(rep_n      === RPT_LEN,     "T8 报告 = 208 Byte");
        check(got_vec    === exp_vec,     "T9 报告字节逐字节正确");
        check((wacc >= 36) && (prb_val_bad === 1'b0),
                                          "T10 探针写值 = 字地址（36 word）");
        check((wacc >= 36) && (prb_a_bad === 1'b0) && (prb_b_bad === 1'b0) &&
              (prb_a_first === 32'h1000) && (prb_b_first === 32'h1035),
                                          "T11 探针写地址连续且基址正确（32+4 word）");

        $display("========================================");
        $display("  断言总数 %0d，失败 %0d", total, errors);
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("========================================");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
