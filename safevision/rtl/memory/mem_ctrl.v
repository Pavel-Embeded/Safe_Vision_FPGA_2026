// ============================================================================
// mem_ctrl.v — SDRAM IP wrapper（SafeVision 阶段 9 · rtl/memory）
// ----------------------------------------------------------------------------
// 依据：手册 7.9「阶段 9：SDRAM 原理」（B 的边界止于 wrapper 的请求/响应接口
//       与逻辑字节地址）、7.11「Burst 突发传输」
//       docs/interface_spec.md §3.4「mem_ctrl（SDRAM IP wrapper）」
//       docs/interface_spec.md §一「地址：只传逻辑字节地址（32bit），物理 32bit
//         word 地址由 mem_ctrl wrapper 内部转换」
//
// 职责：把业务侧的逻辑【字节地址】转成模型/IP 需要的【字地址】（addr >> 2），
//       按 ready 握手转发请求，并在请求长时间得不到响应时拉高 mem_error。
//
// ★ 硬规定（interface_spec §一 / 蓝图 D-4）：
//     对外只暴露逻辑字节地址，业务模块（frame_writer / pcm_ring / frame_reader
//     等）内**禁止裸物理地址运算**。物理地址转换只发生在本模块内。
//     换 SDRAM IP 或 wrapper 版本时，全链地址无需改动。
//
// ★ 说明：本 wrapper 以行为级 sdram_model 为后端完成仿真验证；上板时把
//   sdram_* 这一组端口接到安路官方 SDRAM IP 的请求/响应接口即可（手册 7.9：
//   最终使用官方 IP wrapper）。IP 版本与参数以 APUG011 与板级报告为准。
//
// ★ 踩过的坑：字节地址低 2 位（byte within word）在转字地址时被丢弃。
//   32bit word 内的高低半由 frame_address_gen 的 word_phase 指出，写侧用
//   wstrb 选择字节——**不要把字节地址直接当字地址用**，否则每次访问都会
//   落到 4 倍远处。
// ============================================================================

module mem_ctrl #(
    // 请求在 ready 持续为低时等待多少拍后判超时（mem_error 锁存，直到复位）
    // mem_clk = 125MHz，4096 拍 ≈ 32.8us，远大于一次正常访问的往返拍数
    parameter [31:0] TO_MEM = 32'd4096
)(
    input  wire        clk,            // mem_clk 125MHz
    input  wire        rst_n,

    // ---- 对外（业务侧，逻辑字节地址域）----
    output wire        init_done,      // SDRAM 初始化完成
    input  wire        req,            // 访问请求
    input  wire        wr,             // 1=写 0=读
    input  wire [31:0] addr,           // ★ 逻辑字节地址
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,          // 字节选通
    output wire [31:0] rdata,
    output wire        rdata_valid,
    output wire        ready,          // 可接受请求（valid/ready 握手）
    output wire        mem_error,      // 超时后拉高（锁存）

    // ---- 到 SDRAM 模型 / 官方 IP（字地址域）----
    output wire        sdram_req,
    output wire        sdram_wr,
    output wire [31:0] sdram_addr,     // 字地址
    output wire [31:0] sdram_wdata,
    output wire [3:0]  sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_rdata_valid,
    input  wire        sdram_ready,
    input  wire        sdram_init_done
);

    // ------------------------------------------------------------------------
    // 逻辑字节地址 -> 字地址（丢弃 word 内低 2 位）
    // ------------------------------------------------------------------------
    assign sdram_addr = {2'b00, addr[31:2]};

    assign init_done      = sdram_init_done;
    assign sdram_req      = req;
    assign sdram_wr       = wr;
    assign sdram_wdata    = wdata;
    assign sdram_wstrb    = wstrb;

    assign rdata          = sdram_rdata;
    assign rdata_valid    = sdram_rdata_valid;
    assign ready          = sdram_ready;

    // ------------------------------------------------------------------------
    // 超时监测：请求未被接受（ready 一直为低）累计超过 TO_MEM 拍 -> mem_error
    //   注意：只要 ready 拉高（请求被接受）就清零计数器，正常访问永不误报。
    //   该逻辑放在 case/状态机之外，对所有状态生效。
    // ------------------------------------------------------------------------
    reg [31:0] to_cnt;
    reg        mem_error_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            to_cnt      <= 32'd0;
            mem_error_r <= 1'b0;
        end else begin
            if (req && !sdram_ready) begin
                if (to_cnt >= TO_MEM) mem_error_r <= 1'b1;   // 锁存
                else                  to_cnt     <= to_cnt + 32'd1;
            end else begin
                to_cnt <= 32'd0;
            end
        end
    end

    assign mem_error = mem_error_r;

endmodule