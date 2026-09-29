// ============================================================================
// spi_byte_rx.v — SPI 字节接收（SafeVision B 链 · 学习阶段 1）
// ----------------------------------------------------------------------------
// 依据：手册 7.1 / 7.2
//       固件约定：SD 卡在 SPI 模式下固定 MSB first；SPI mode0 在 SCLK 上升沿采样。
//
// 定位：这是【学习阶段的独立可仿真件】——用它把"位序与采样沿"一次定死，
//       用仿真喂一串预设比特验证字节与位序，再进 spi_master。
//       注意：它靠检测 sclk 上升沿工作，因此只能用于仿真/慢速验证；
//       spi_master 内部不依赖边沿检测，而是由分频 tick 直接驱动采样。
//
// ★ 手册 7.1 易错点：采样沿选在跳变沿上 -> 本模块只在【上升沿】采样。
// ============================================================================

module spi_byte_rx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       sclk,          // 由 SPI 主机产生的时钟
    input  wire       miso,          // 从机数据

    input  wire       clear,         // 高有效：清零位计数与移位寄存器（字节之间用）

    output reg  [7:0] rx_byte,       // 收满 8 位的结果
    output reg        rx_valid       // 收满后拉高 1 拍
);

    reg       sclk_d;
    reg [2:0] bit_cnt;
    reg [7:0] sreg;

    wire sclk_rise = sclk & ~sclk_d;     // 上升沿检测

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_d   <= 1'b0;
            bit_cnt  <= 3'd0;
            sreg     <= 8'h00;
            rx_byte  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            sclk_d   <= sclk;
            rx_valid <= 1'b0;            // 默认单拍脉冲

            if (clear) begin
                bit_cnt <= 3'd0;
                sreg    <= 8'h00;
            end else if (sclk_rise) begin
                sreg <= {sreg[6:0], miso};        // MSB first：先到的比特最终落在 bit7
                if (bit_cnt == 3'd7) begin
                    bit_cnt  <= 3'd0;
                    rx_byte  <= {sreg[6:0], miso};   // 非阻塞：用当前值拼最后一位
                    rx_valid <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 3'd1;
                end
            end
        end
    end

endmodule