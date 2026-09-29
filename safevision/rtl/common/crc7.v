// ============================================================================
// crc7.v — SD 命令 CRC7 字节步进（SafeVision 通用件）
// ----------------------------------------------------------------------------
// 说明：
//        手册 7.3：SPI 模式下只有 CMD0 与 CMD8 会被卡校验 CRC7。
//
// 算法口径：
//     poly     = 0x09          (x^7 + x^3 + 1)
//     init     = 0x00
//     MSB first，无反射，无终值异或
//
// ★ 为什么值得单独做一个模块：
//   现在 spi_master / sd_initializer 里的 CRC 字节是【硬编码常数】
//   （`SD_CRC_CMD0 = 8'h95`、`SD_CRC_CMD8 = 8'h87`，即 {CRC7, 1'b1}）。
//   硬编码本身没错，但如果抄错一个 bit，表现是"CMD0 发出去卡毫无反应"，
//   而且仿真里不会报错（卡模型不校验 CRC7）——上板才炸。
//   本模块提供"可计算的 CRC7"，配套的 tb_crc.sv 用它去反推
//   0x4A / 0x43，等于把这两个魔数**钉死在对数上**。
//
// 用法与 crc16_ccitt 同构（纯组合步进器，无状态）：
//     crc7 u_crc (.crc_in(crc_acc), .data(cmd_byte), .crc_out(crc_next));
//   40 bit 命令帧（1 Byte 命令 + 4 Byte 参数）走 5 次后得到 CRC7；
//   上线前补 1 位结束位：{crc7, 1'b1} 才是要发出去的那个字节。
// ============================================================================
module crc7 (
    input  wire [6:0] crc_in,     // 当前累加值（首字节前给 7'h00）
    input  wire [7:0] data,       // 要喂进去的字节
    output wire [6:0] crc_out     // 吃完这个字节后的值
);

    function [6:0] step;
        input [6:0] c;
        input [7:0] d;
        integer i;
        reg [6:0] t;
        begin
            t = c;
            for (i = 7; i >= 0; i = i - 1) begin
                if (t[6] ^ d[i])
                    t = (t << 1) ^ 7'h09;
                else
                    t = (t << 1);
            end
            step = t;
        end
    endfunction

    assign crc_out = step(crc_in, data);

endmodule