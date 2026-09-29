// ============================================================================
// shift_reg.v — 通用移位寄存器（SafeVision B 链 · 学习阶段 1）
// ----------------------------------------------------------------------------
// 依据：手册 7.1「移位寄存器是 B 这条链上的第一块砖」
//       核心写法 sreg <= {sreg[6:0], miso_d}，8 拍后得到一个完整字节
//
// 一个模块同时服务收/发两个方向（MSB first）：
//   发送：ser_out = data_out[MSB]，shift_en 时左移并把 ser_in 补进 LSB
//   接收：同样左移，8 拍后先到的比特落在 MSB
//
// ★ 手册 7.1 明列易错点：位序写反 / 用系统时钟代替 SCLK / 采样沿选在跳变沿上。
//   本模块工作在 clk 域，采样沿由调用方（spi_byte_rx）决定，不在模块内部猜。
//
// 过关自测（手册）：喂 10110110 波形，第 8 个采样沿后 data_out 等于该字节。
// ============================================================================

module shift_reg #(
    parameter integer WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,

    input  wire             load_en,        // 并行装载（发命令前用）
    input  wire [WIDTH-1:0] load_data,
    input  wire             shift_en,       // 移位使能
    input  wire             ser_in,         // 串行输入；发送时补 1'b1 保持空闲高

    output reg  [WIDTH-1:0] data_out,
    output wire             ser_out         // 当前最高位 = 下一个要发出的比特
);

    assign ser_out = data_out[WIDTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= {WIDTH{1'b0}};
        end else if (load_en) begin
            data_out <= load_data;
        end else if (shift_en) begin
            data_out <= {data_out[WIDTH-2:0], ser_in};   // MSB first：左移，新比特进 LSB
        end
    end

endmodule