// 74LS138 3-8 线译码器 —— 行为级描述
`timescale 1ns / 1ps

module ls74ls138 (
    input  wire [2:0] A,      // 地址输入 A2 A1 A0
    input  wire       G1,     // 使能端，高电平有效
    input  wire       G2A_n,  // 使能端，低电平有效
    input  wire       G2B_n,  // 使能端，低电平有效
    output reg  [7:0] Y_n     // 8 路输出，低电平有效
);

    // 行为描述：使能有效时按地址选通一路输出，其余为高
    always @(*) begin
        if (G1 && !G2A_n && !G2B_n) begin
            case (A)
                3'd0: Y_n = 8'b1111_1110;  // Y0 有效
                3'd1: Y_n = 8'b1111_1101;  // Y1 有效
                3'd2: Y_n = 8'b1111_1011;  // Y2 有效
                3'd3: Y_n = 8'b1111_0111;  // Y3 有效
                3'd4: Y_n = 8'b1110_1111;  // Y4 有效
                3'd5: Y_n = 8'b1101_1111;  // Y5 有效
                3'd6: Y_n = 8'b1011_1111;  // Y6 有效
                3'd7: Y_n = 8'b0111_1111;  // Y7 有效
                default: Y_n = 8'b1111_1111;
            endcase
        end
        else
            Y_n = 8'b1111_1111;  // 任一使能无效，全部输出高电平（禁止译码）
    end

endmodule
