// ============================================================================
// frame_writer.v — 把 RGB565 像素流写进指定槽，写完置 slot_valid（SafeVision 阶段 10）
// ----------------------------------------------------------------------------
// 依据：手册 7.10「Frame Buffer 帧缓存」、7.16.1「DMA 思想：把搬运抽象出来」
//         （source=SD FIFO、dest=SDRAM 帧区、length=一帧像素数、start 启动、
//           done 完成；done 有效后产生 frame_ready 与 CRC 抽检结果）
//       手册 7.11「Burst 突发传输」（本模块按 word 粒度发起写请求，突发由 arbiter 聚合）
//       docs/interface_spec.md §3.4「slot_writer」（本工程按新结构改名 frame_writer，
//         端口语义照文档）、§一（valid&&ready 双判）、§五（地址表）、§6.2（err_detail）
//
// 职责：把上游的 RGB565 像素流（din/din_valid/din_ready）打包成 32bit word 写进
//       slot_base 指定的槽；一帧 640×480=307200 像素写完并做抽样 CRC 比对后，
//       置 slot_valid[slot_sel]。
//
// 端口对应（interface_spec §3.4 slot_writer）：
//   slot_sel / slot_base / din / din_valid / din_ready / wr_req / wr_addr /
//   wr_data / wr_len / wr_ready / wr_done / slot_valid / crc_ok / crc_value /
//   px_cnt / wr_error  (+ err_code / err_detail 登记细分码)
//
// ★★ 核心安全规则（手册 7.10 与 interface_spec §3.4 原文口径）：
//     slot_valid 只有在一整帧写完 + CRC 通过后才置位。
//     **未置位不许读**——这条规则把"半幅图被显示"的可能性在结构上排除；
//     A 侧像素读引擎在 slot_valid=1 之前绝不能读该槽。
//
// ★ 一帧必须正好 640×480 = 307200 个像素，多一个少一个都算错：
//     - 少一个（提前 EOF / 上游断流）-> wr_error + DET_FS_SHORT
//     - 多一个（像素数超限）        -> wr_error + DET_BMP_SIZE
//   两者都不会置 slot_valid。
//
// ★ 两个像素打包成一个 32bit word：**低半 = 先到的像素**，高半 = 后到的像素。
//   （与"新字节从高端进"的小端口径一致；写反了会导致相邻像素互换。）
//
// ★ 抽样 CRC：每 1024 个 word 取一个抽样点，算法 CRC16-CCITT XMODEM
//   （poly 0x1021，init 0x0000，MSB first），与 sd_sector_reader.v 里那份实现一致。
//   本模块对"源打包 word"与"总线上真正写出的 word"各算一遍并比对，
//   等价于一次打包/写通路的自检：crc_ok = (crc_src == crc_bus)。
//   （注：本模块端口没有回读通道，故 crc_ok 定义为写侧两路 CRC 的一致性 + 帧计数正确；
//     真正的 SDRAM 写回读校验需读通道，留待 frame_reader 落地后并入。）
//
// ★ 越界写：写请求地址必须落在 [slot_base, slot_base+SLOT_SPAN) 且 slot_base 合法
//   （槽基地址 + 单槽预留不得越过 SDRAM 可见容量）。越界一律拒绝并报 DET_BMP_TRUNC。
//   正常 x∈[0,640)、y∈[0,480) 时偏移 < 0x96000 < SLOT_SPAN，槽内写永不越界；
//   本检查是防御性设计，捕捉非法 slot_base（配置错误）这类穿越。
//
// ★ 实测/文档踩过的坑（interface_spec §一，本项目真实踩过）：
//   1) 从上游收像素必须用 `din_valid && din_ready` 双判，不能只判 din_valid，
//      否则反压期间会把同一个像素吃掉很多次，px_cnt 与数据流瞬间错位。
//   2) 下游取走 word 的清零逻辑（wr_pending / bus_idx / crc_bus）放在状态机之外、
//      对所有状态生效；写在接收态里会在"最后一拍跳走"时漏清。
// ============================================================================
`include "safevision_defs.vh"

module frame_writer #(
    parameter [9:0]  FRAME_WIDTH     = `SV_FRAME_WIDTH,
    parameter [9:0]  FRAME_HEIGHT    = `SV_FRAME_HEIGHT,
    parameter [31:0] BYTES_PER_PIXEL = `SV_RGB565_BYTES_PER_PX,
    parameter [18:0] PIX_PER_FRAME   = `SV_FRAME_PIXELS,      // 640*480
    parameter integer SAMPLE_STRIDE  = 1024,            // 每 1024 word 取一个抽样点
    parameter [31:0] GAP_TIMEOUT     = 32'd512,         // clocks; override for SD streaming latency
    parameter [31:0] SLOT_SPAN       = `SV_IMG_ALIGN_BYTES,     // 单槽预留（§5 地址表）
    parameter [31:0] MEM_VISIBLE     = `SV_MEM_VISIBLE_BYTES,    // SDRAM 对外可见容量 4 MiB（§3.4）
    parameter integer EXACT_SAMPLE_COMPARE=0
)(
    input  wire        clk,             // mem_clk
    input  wire        rst_n,

    // ---- 控制 / 目标槽 ----
    input  wire        start,           // 单拍：开始写一帧
    input  wire [1:0]  slot_sel,        // 目标槽
    input  wire [31:0] slot_base,       // 槽起始逻辑字节地址（取值见 §5）

    // ---- 来自 bmp_unpack 的 RGB565 像素流 ----
    input  wire [15:0] din,
    input  wire        din_valid,
    output wire        din_ready,

    // ---- 到 mem_arbiter / mem_ctrl 的写通道 ----
    output wire        wr_req,
    output wire [31:0] wr_addr,         // 逻辑字节地址
    output wire [31:0] wr_data,         // 2 像素/word
    output wire [15:0] wr_len,          // 突发长度（本模块逐 word 请求，长度=1）
    input  wire        wr_ready,
    output reg         wr_done,         // 单拍：一帧全部 word 写出并完成 CRC 结算

    // ---- 结果 / 状态 ----
    output reg  [3:0]  slot_valid,      // ★ 置位后 A 才允许读该槽
    output reg         crc_ok,
    output reg  [15:0] crc_value,
    output reg  [18:0] px_cnt,          // 应等于 307200
    output reg         wr_error,
    output reg  [7:0]  err_code,        // 对外主码
    output reg  [7:0]  err_detail       // B 链内部细分码
);

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam S_IDLE = 1'b0,
               S_RUN  = 1'b1;

    // interface_spec §6.1/§6.2 已登记、但 fault_code_defs.vh 暂未收录的两个码，
    // 在本模块局部登记（不改公共头文件；CRC 写校验失败用它们上报）。
    localparam [7:0] ERR_SDRAM_XFER   = 8'h04;   // §6.1 0x04 SDRAM 读写校验失败
    localparam [7:0] DET_SDRAM_VERIFY = 8'h42;   // §6.2 0x42 SDRAM 写回读校验失败

    reg        state;
    // Track the counter's full predicate at the same accepting edge. This
    // removes a wide px_cnt equality from the pixel-ready/error/state cone;
    // there is no extra pipeline cycle at the final pixel or publication.
    reg        frame_full;
    reg [31:0] base_reg;      // 锁存的槽基地址
    reg [1:0]  slot_sel_q;    // 锁存的目标槽
    reg        have_lo;       // 是否已收到配对中的低半（先到）像素
    reg [15:0] lo_pix;        // 暂存的低半像素
    reg [9:0]  x_cnt;         // 当前 word 对应像素对的 x（偶数）
    reg [9:0]  y_cnt;         // 当前 word 对应像素对的 y
    reg [31:0] src_idx;       // 已打包 word 数（源侧）
    reg [31:0] bus_idx;       // 已写出 word 数（总线侧）
    (* preserve="true",keep="true" *)reg sample_mismatch;
    reg [15:0] crc_src;       // 源侧抽样 CRC
    reg [15:0] crc_bus;       // 总线侧抽样 CRC
    reg        wr_pending;    // 有一个 word 待写出
    reg [31:0] wr_addr_r;
    (* preserve="true",keep="true" *)reg [31:0] wr_data_r;
    reg        crc_src_pend;  // CRC 源侧提交事件（迟一拍结算，见下方时序说明）
    (* preserve="true",keep="true" *)reg [31:0] crc_pair_q;    // 与事件对齐锁存的像素对载荷
    localparam integer GAP_W = (GAP_TIMEOUT < 2) ? 1 : $clog2({1'b0,GAP_TIMEOUT}+33'd1);
    reg [GAP_W-1:0] gap_cnt;  // minimal width, including SD latency >65535 clocks

    // ------------------------------------------------------------------------
    // 二维坐标 -> 字节地址（复用 frame_address_gen，公式与手册一致）
    // ------------------------------------------------------------------------
    wire [31:0] cur_byte_addr;
    wire [31:0] cur_offset;
    wire [29:0] cur_word_addr;
    wire        cur_word_phase;

    frame_address_gen #(
        .FRAME_WIDTH     (FRAME_WIDTH),
        .BYTES_PER_PIXEL (BYTES_PER_PIXEL)
    ) u_addr_gen (
        .slot_base (32'd0),
        .x         (x_cnt),
        .y         (y_cnt),
        .byte_addr (cur_offset),
        .word_addr (cur_word_addr),
        .word_phase(cur_word_phase)
    );
    assign cur_byte_addr = base_reg + cur_offset;

    // ------------------------------------------------------------------------
    // 组合信号
    // ------------------------------------------------------------------------
    wire running    = (state == S_RUN);

    // 只在运行中、无待写 word、一帧未满时才收像素
    assign din_ready = running && !wr_pending && !frame_full;
    assign wr_req    = running && wr_pending;
    assign wr_addr   = wr_addr_r;
    assign wr_data   = wr_data_r;
    assign wr_len    = 16'd1;

    wire wr_accept = wr_req && wr_ready;      // 下游取走一个 word
    wire px_accept = din_valid && din_ready;  // ★ valid && ready 双判

    // ------------------------------------------------------------------------
    // CRC16-CCITT (XMODEM) 抽样校验：算法实现集中在 rtl/common/crc16_ccitt.v
    //   （此前本模块与 sd_sector_reader.v 各写了一份同名函数，两处口径必须
    //     永远一致，故抽为公共模块；改算法只需改那一处。）
    //   一个 32bit word 按大端（先高字节）逐字节喂入 = 级联 4 级。
    // ------------------------------------------------------------------------
    // 源侧打包 word（高半=后到，低半=先到），两处引用同一根线，避免写反
    wire [31:0] px_pair = {din, lo_pix};

    wire [15:0] crc_bus_w1, crc_bus_w2, crc_bus_w3;
    wire [15:0] crc_bus_next;
    crc16_ccitt u_crc_bus_0 (.crc_in(crc_bus),    .data(wr_data_r[31:24]), .crc_out(crc_bus_w1));
    crc16_ccitt u_crc_bus_1 (.crc_in(crc_bus_w1), .data(wr_data_r[23:16]), .crc_out(crc_bus_w2));
    crc16_ccitt u_crc_bus_2 (.crc_in(crc_bus_w2), .data(wr_data_r[15:8]),  .crc_out(crc_bus_w3));
    crc16_ccitt u_crc_bus_3 (.crc_in(crc_bus_w3), .data(wr_data_r[7:0]),   .crc_out(crc_bus_next));

    wire [15:0] crc_src_w1, crc_src_w2, crc_src_w3;
    wire [15:0] crc_src_next;
    // ★ 时序（mem→mem 多米诺，2026-10-06）：源侧 CRC 改为对**锁存载荷**
    //   crc_pair_q 计算、迟一拍提交（见主状态机里的 crc_src_pend）。
    //   这使"px_cnt → frame_full → din_ready → px_accept → CE"的 5 级长锥
    //   （net 占 75%）退化为寄存器直驱的短 CE；级联本身（crc_src → crc_src_next
    //   → crc_src.d）深度不变，且输入从输入脚/lo_pix 换成寄存器只会更短。
    //   语义不变：配对完成间隔 ≥2 拍（have_lo 翻转），迟一拍不丢提交；帧满
    //   结算最早在提交后第 2 个边沿读 crc_src（wr_pending 先占用 1 拍），余 1 拍。
    // Legacy clients retain their exact CRC16-source behavior. Resident
    // loading compares the two independently captured sampled WORDS instead:
    // equality is stronger than equality of16-bit CRCs and cannot collide.
    // The bus CRC16 output remains unchanged for clients which observe it;
    // unused CRC logic can be pruned in the production sink.
    generate if(!EXACT_SAMPLE_COMPARE)begin:legacy_source_crc
    crc16_ccitt u_crc_src_0 (.crc_in(crc_src),    .data(crc_pair_q[31:24]), .crc_out(crc_src_w1));
    crc16_ccitt u_crc_src_1 (.crc_in(crc_src_w1), .data(crc_pair_q[23:16]), .crc_out(crc_src_w2));
    crc16_ccitt u_crc_src_2 (.crc_in(crc_src_w2), .data(crc_pair_q[15:8]),  .crc_out(crc_src_w3));
    crc16_ccitt u_crc_src_3 (.crc_in(crc_src_w3), .data(crc_pair_q[7:0]),   .crc_out(crc_src_next));
    end else begin:exact_source_sample
      assign crc_src_next=16'd0;
    end endgenerate
    wire sample_check_ok=EXACT_SAMPLE_COMPARE?!sample_mismatch:(crc_src==crc_bus);


    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            base_reg   <= 32'd0;
            slot_sel_q <= 2'd0;
            have_lo    <= 1'b0;
            lo_pix     <= 16'd0;
            x_cnt      <= 10'd0;
            y_cnt      <= 10'd0;
            src_idx    <= 32'd0;
            bus_idx    <= 32'd0;
            crc_src    <= 16'd0;sample_mismatch<=0;
            crc_bus    <= 16'd0;
            wr_pending <= 1'b0;
            wr_addr_r  <= 32'd0;
            wr_data_r  <= 32'd0;
            crc_src_pend <= 1'b0;
            crc_pair_q   <= 32'd0;
            gap_cnt    <= 16'd0;
            wr_done    <= 1'b0;
            slot_valid <= 4'b0000;
            crc_ok     <= 1'b0;
            crc_value  <= 16'd0;
            px_cnt     <= 19'd0;
            frame_full <= (PIX_PER_FRAME == 19'd0);
            wr_error   <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
        end else begin
            // 默认单拍脉冲
            wr_done <= 1'b0;

            // ---- CRC 源侧：迟一拍提交（时序切分，见 crc_src_next 处说明）----
            // 先消费后登记（源序）：即便消费与新登记同拍，后者也不会被吞掉。
            if (!EXACT_SAMPLE_COMPARE && crc_src_pend) begin
                crc_src      <= crc_src_next;
                crc_src_pend <= 1'b0;
            end

            case (state)
                // ============================================================
                S_IDLE: begin
                    if (start) begin
                        // 槽基地址合法性：4 Byte 对齐 + 不越过 SDRAM 可见容量
                        // Subtract the bound before comparison: adding a large
                        // base could wrap to zero and admit an illegal address.
                        if ((slot_base[1:0] != 2'b00) || (SLOT_SPAN > MEM_VISIBLE) ||
                            (slot_base > (MEM_VISIBLE - SLOT_SPAN))) begin
                            // 越界/非法槽基地址：拒绝，不发任何写，不置 slot_valid
                            wr_error   <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_BMP_TRUNC;
                            crc_ok     <= 1'b0;
                        end else begin
                            base_reg   <= slot_base;
                            slot_sel_q <= slot_sel;
                            have_lo    <= 1'b0;
                            x_cnt      <= 10'd0;
                            y_cnt      <= 10'd0;
                            src_idx    <= 32'd0;
                            bus_idx    <= 32'd0;
                            crc_src    <= 16'd0;sample_mismatch<=0;
                            crc_bus    <= 16'd0;
                            wr_pending <= 1'b0;
                            gap_cnt    <= 16'd0;
                            px_cnt     <= 19'd0;
                            frame_full <= (PIX_PER_FRAME == 19'd0);
                            wr_error   <= 1'b0;
                            err_code   <= `ERR_NONE;
                            err_detail <= `DET_NONE;
                            // ★ 不清 slot_valid：重写期间保留上一帧的可用画面
                            state      <= S_RUN;
                        end
                    end
                end

                // ============================================================
                S_RUN: begin
                    // ---- (1) 写通道握手：下游取走一个 word ----
                    //     清零/记账放在状态机逻辑的最前面，对所有分支生效
                    if (wr_accept) begin
                        wr_pending <= 1'b0;
                        if ((bus_idx % SAMPLE_STRIDE) == 0)begin
                            crc_bus <= crc_bus_next;
                            if(EXACT_SAMPLE_COMPARE && wr_data_r!==crc_pair_q)sample_mismatch<=1;
                        end
                        bus_idx <= bus_idx + 32'd1;
                    end

                    // ---- (2) 收像素：valid && ready 双判 ----
                    if (px_accept) begin
                        px_cnt <= px_cnt + 19'd1;
                        if (px_cnt == (PIX_PER_FRAME - 19'd1)) frame_full <= 1'b1;
                        if (!have_lo) begin
                            // 配对中的低半（先到像素）
                            have_lo <= 1'b1;
                            lo_pix  <= din;
                        end else begin
                            // 收齐一对，打包成一个 word
                            have_lo <= 1'b0;
                            // 越界写检查（防御性，正常永不触发）
                            // A validated base plus offset<SLOT_SPAN cannot
                            // wrap or exceed MEM_VISIBLE. Check the offset so
                            // the 125MHz enable path avoids add+two compares.
                            if (cur_offset >= SLOT_SPAN) begin
                                wr_error   <= 1'b1;
                                err_code   <= `ERR_MEDIA_INVALID;
                                err_detail <= `DET_BMP_TRUNC;
                                crc_ok     <= 1'b0;
                                state      <= S_IDLE;   // 拒绝越界写
                            end else begin
                                wr_pending <= 1'b1;
                                wr_addr_r  <= cur_byte_addr;
                                wr_data_r  <= px_pair;       // 高半=后到，低半=先到
                                // ★ 抽样命中：不再就地算 crc_src，改为登记
                                //   "事件 + 载荷"、下一拍由块首的消费逻辑结算
                                //   （时序理由与等价性见 crc_src_next 处说明）
                                if (((EXACT_SAMPLE_COMPARE?bus_idx:src_idx) % SAMPLE_STRIDE) == 0) begin
                                    crc_src_pend <= 1'b1;
                                    crc_pair_q   <= px_pair;
                                end
                                src_idx <= src_idx + 32'd1;
                                // 推进像素对坐标（x 每次 +2）
                                if (x_cnt == (FRAME_WIDTH - 10'd2)) begin
                                    x_cnt <= 10'd0;
                                    y_cnt <= y_cnt + 10'd1;
                                end else begin
                                    x_cnt <= x_cnt + 10'd2;
                                end
                            end
                        end
                    end

                    // ---- (3) 一帧满后的走向 ----
                    if (frame_full && !wr_pending) begin
                        if (din_valid) begin
                            // 上游还在给像素 -> 像素数超限
                            wr_error   <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_BMP_SIZE;
                            crc_ok     <= 1'b0;
                            state      <= S_IDLE;
                        end else begin
                            // 正好 307200 像素且全部写出：结算抽样 CRC
                            crc_value <= crc_bus;
                            crc_ok    <= sample_check_ok;
                            if (sample_check_ok) begin
                                // ★ 只有"整帧写完 + CRC 通过"两件事都成立才置位
                                slot_valid[slot_sel_q] <= 1'b1;
                                wr_done   <= 1'b1;
                            end else begin
                                // CRC 比对失败：不置 slot_valid、不发 wr_done
                                wr_error   <= 1'b1;
                                err_code   <= ERR_SDRAM_XFER;
                                err_detail <= DET_SDRAM_VERIFY;
                            end
                            state     <= S_IDLE;
                        end
                    end
                    // ---- (4) 帧内无进展超时（提前 EOF / 上游断流）----
                    else if (!frame_full) begin
                        if (px_accept || wr_accept) begin
                            gap_cnt <= 16'd0;
                        end else if (gap_cnt >= GAP_TIMEOUT) begin
                            wr_error   <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_FS_SHORT;
                            crc_ok     <= 1'b0;
                            state      <= S_IDLE;
                        end else begin
                            gap_cnt <= gap_cnt + 16'd1;
                        end
                    end
                    // frame_full && wr_pending：等最后一个 word 被取走，不做别的
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
