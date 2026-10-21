// ============================================================================
// sync_fifo.v — 同域同步 FIFO（带 almost_full / almost_empty / data_count）
// ----------------------------------------------------------------------------
// 文件职责：
//   单个时钟域内的通用 FIFO，供 error_report 的事件队列、水位统计与
//   单元测试使用。不做任何跨域，跨域一律交给安路软 FIFO IP（见 interface_spec
//   §一 CDC 约定：IP 的 rst 异步高有效，必须取反接入）。
//
// 依据：
//   手册 7.8 阶段 8「FIFO（B 要比 A 理解得更深）」：
//     「重点关注 full、empty、almost_full、almost_empty 与 data_count；
//      ★ almost_full 才是真正的反压手段，等 full 再反压已经晚了。水位阈值
//      必须给出推导依据，并按设计目标（待实测）标注。」
//   手册 7.8 学习卡片「FIFO 与水位」易错点：
//     「只在 full 时反压导致丢数；data_count 直接跨域；忘记读出有延迟」
//   docs/interface_spec.md §7 决策 D-2 / D-6：全链只保留一种 FIFO 读出语义。
//
// 关键设计决策：
//   1) 读出方式 = Show-Ahead（FWFT）：empty=0 时 dout 即队首数据，无需预取一拍。
//      理由与 D-6 一致——「全链只保留一种 FIFO 语义，降低 A/C 双方理解成本与
//      出错面」。本模块是同域件，组合读 dout 综合即分布式 RAM，代价可接受；
//      跨域的像素/音频 FIFO 用 IP 的 SHOW_AHEAD=Enable 得到同样语义。
//   2) data_count 位宽取 $clog2(DEPTH)+1，因此【能取到 DEPTH 本身】。
//      写成 $clog2(DEPTH) 时 DEPTH=64 只能表示 0..63，满时会回绕成 0，
//      水位统计与反压判断全部失真（这是 FIFO 设计里最常见的位宽坑）。
//   3) almost_full 用 cnt >= ALMOST_FULL_TH、almost_empty 用 cnt <= ALMOST_EMPTY_TH；
//      上游必须用 almost_full 提前反压，用 full 反压时突发已经打到脸上。
//   4) 阈值是按"SD 一次突发 512 Byte + 仲裁往返延迟"的量级给的设计目标，
//      真实产品值待板上实测后回填（手册 7.12：报告只接受实测口径）。
//
// 实测踩过的坑：
//   - 读空时 rd_en 拉高不得改动 rd_ptr，否则"空读"会偷走后面才写进来的数据；
//     本模块用 rd_fire = rd_en & ~empty 门控，天然免疫。
//   - 读写同拍时计数必须保持不变，且不能写错指针。
// ============================================================================

module sync_fifo #(
    parameter W                = 16,
    parameter DEPTH            = 64,
    parameter ALMOST_FULL_TH   = 48,
    parameter ALMOST_EMPTY_TH  = 4
)(
    input  wire            clk,
    input  wire            rst_n,

    // ---- 写侧 ----
    input  wire            wr_en,
    input  wire [W-1:0]    din,
    output wire            full,
    output wire            almost_full,

    // ---- 读侧（FWFT：empty=0 时 dout 即队首）----
    input  wire            rd_en,
    output wire [W-1:0]    dout,
    output wire            empty,
    output wire            almost_empty,

    // ---- 水位（位宽 = clog2(DEPTH)+1，能表示到 DEPTH 本身）----
    output wire [$clog2(DEPTH):0] data_count
);

    localparam LOG2 = $clog2(DEPTH);      // 指针位宽；DEPTH=64 -> 6
    // data_count 位宽 = LOG2+1，最大能表示 DEPTH 本身（不是 DEPTH-1）

    reg [W-1:0]    mem [0:DEPTH-1];
    reg [LOG2-1:0] wr_ptr;
    reg [LOG2-1:0] rd_ptr;
    reg [LOG2:0]   cnt;                   // 0 .. DEPTH

    wire wr_fire = wr_en & ~full;
    wire rd_fire = rd_en & ~empty;

    assign full         = (cnt == DEPTH);
    assign almost_full  = (cnt >= ALMOST_FULL_TH);
    assign empty        = (cnt == 0);
    assign almost_empty = (cnt <= ALMOST_EMPTY_TH);
    assign data_count   = cnt;

    // FWFT 读出：队首就在 dout 上，读方拿到 empty 即可判有效
    assign dout = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {LOG2{1'b0}};
            rd_ptr <= {LOG2{1'b0}};
            cnt    <= {(LOG2+1){1'b0}};
        end else begin
            if (wr_fire) begin
                mem[wr_ptr] <= din;
                if (wr_ptr == DEPTH - 1) begin
                    wr_ptr <= {LOG2{1'b0}};
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (rd_fire) begin
                if (rd_ptr == DEPTH - 1) begin
                    rd_ptr <= {LOG2{1'b0}};
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end

            // 读写同拍时水位不变；否则单边增减
            if (wr_fire && rd_fire) begin
                cnt <= cnt;
            end else if (wr_fire) begin
                cnt <= cnt + 1'b1;
            end else if (rd_fire) begin
                cnt <= cnt - 1'b1;
            end
        end
    end

endmodule