// ============================================================================
// uart_tx.v — UART 发送（SafeVision 第 9 章三人公共调试模块 · 雏形）
// ----------------------------------------------------------------------------
// 依据：手册第 9 章「发送侧只需按波特率计数移位，位中点采样是接收侧的事」
//
// 用途：阶段 5 把 SD 读出的 512 Byte 回传到电脑逐字节比对。
//       后续 C 的 UART 日志/命令回显会在此基础上扩展（收+发）。
//
// 帧格式：115200 8N1，LSB 先发
// ============================================================================

module uart_tx #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_valid,     // 单拍脉冲，请求发送
    input  wire [7:0] tx_data,
    output wire       tx_ready,     // 可接受新字节

    output reg        txd           // 串行输出，空闲为高
);

    // 每 bit 的时钟数：100MHz / 115200 = 868.05 -> 868（误差 0.006%，远小于 2% 容限）
    localparam integer DIV = CLK_FREQ / BAUD;

    localparam [1:0] U_IDLE  = 2'd0,
                     U_START = 2'd1,
                     U_DATA  = 2'd2,
                     U_STOP  = 2'd3;

    reg  [1:0]  state;
    // Exact original divider range; retain16-bit behavior for unsupported DIV.
    localparam integer COUNTER_W=(DIV>=1&&DIV<=65536)?((DIV>1)?(($clog2(DIV)>1)?$clog2(DIV)-1:1):1):16;
    reg [COUNTER_W-1:0] div_cnt;
    reg  [2:0]  bit_idx;
    reg  [7:0]  shifter;

    assign tx_ready = (state == U_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= U_IDLE;
            div_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shifter <= 8'h00;
            txd     <= 1'b1;              // 空闲高
        end else begin
            case (state)
                // ------------------------------------------------------------
                U_IDLE: begin
                    txd     <= 1'b1;
                    div_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_valid) begin
                        shifter <= tx_data;
                        state   <= U_START;
                    end
                end
                // ---- 起始位：拉低 1 个 bit 时间 ----------------------------
                U_START: begin
                    txd <= 1'b0;
                    if (div_cnt == DIV - 1) begin
                        div_cnt <= 16'd0;
                        state   <= U_DATA;
                    end else begin
                        div_cnt <= div_cnt + 16'd1;
                    end
                end
                // ---- 8 位数据：LSB 先发 ------------------------------------
                U_DATA: begin
                    txd <= shifter[0];
                    if (div_cnt == DIV - 1) begin
                        div_cnt <= 16'd0;
                        shifter <= {1'b1, shifter[7:1]};   // 补 1 是停止位电平
                        if (bit_idx == 3'd7) begin
                            state <= U_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 16'd1;
                    end
                end
                // ---- 停止位：拉高 1 个 bit 时间 ----------------------------
                U_STOP: begin
                    txd <= 1'b1;
                    if (div_cnt == DIV - 1) begin
                        div_cnt <= 16'd0;
                        state   <= U_IDLE;
                    end else begin
                        div_cnt <= div_cnt + 16'd1;
                    end
                end
                // ------------------------------------------------------------
                default: state <= U_IDLE;
            endcase
        end
    end

endmodule