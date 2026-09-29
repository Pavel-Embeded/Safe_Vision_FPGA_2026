// ============================================================================
// crc16_ccitt.v — CRC16-CCITT (XMODEM) 字节步进（SafeVision 通用件）
// ----------------------------------------------------------------------------
// 依据：《工业级模块化架构蓝图》§4 的 rtl/common/crc16_ccitt.v
//        之前这份算法在 sd_sector_reader.v 与 frame_writer.v 里【各写了一份】，
//        本模块把它抽出来共用，避免"两处 CRC 实现不一致"这种最难查的 bug
//        （与 fat32_cluster_walker 消掉的两份判环逻辑是同一类问题）。
//
// 算法口径（三方必须一致，改这里等于改全链）：
//     poly     = 0x1021        (x^16 + x^12 + x^5 + 1)
//     init     = 0x0000
//     反射     = 无（MSB first）
//     终值异或 = 无
//
// ★ 形态：**纯组合**的"下一拍值"步进器。
//   为什么不写成带寄存器、带 valid/ready 的流式模块：调用方
//   （sd_sector_reader 逐字节收、frame_writer 一次吃 4 字节）都需要在
//   自己的时序里决定什么时候更新累加器，接口形态必须"无状态"才两边都能用。
//   要流式使用，在外面挂一个累加寄存器即可。
//
// 用法：
//     wire [15:0] crc_next;
//     crc16_ccitt u_crc (.crc_in(crc_acc), .data(byte_in), .crc_out(crc_next));
//     // 该吃字节时：crc_acc <= crc_next;
//
//   一次吃 4 字节（大端，先高字节）就级联四级：
//     crc16_ccitt u1 (.crc_in(c0), .data(w[31:24]), .crc_out(c1));
//     crc16_ccitt u2 (.crc_in(c1), .data(w[23:16]), .crc_out(c2));
//     ...
// ============================================================================
module crc16_ccitt (
    input  wire [15:0] crc_in,    // 当前累加值（首字节前给 0x0000）
    input  wire [7:0]  data,      // 要喂进去的字节
    output wire [15:0] crc_out    // 吃完这个字节后的值
);

    function [15:0] step;
        input [15:0] c;
        input [7:0]  d;
        integer i;
        reg [15:0] t;
        begin
            t = c ^ {d, 8'h00};             // 字节与高 8 位异或
            for (i = 0; i < 8; i = i + 1)
                t = t[15] ? ((t << 1) ^ 16'h1021) : (t << 1);
            step = t;
        end
    endfunction

    assign crc_out = step(crc_in, data);

endmodule