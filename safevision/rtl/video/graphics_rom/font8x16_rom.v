


module font8x16_rom #(parameter FONT_FILE="../../../assets/fonts/font8x16.mem")(
    input wire clk, input wire [11:0] addr, output reg [7:0] row_bits);
    reg [7:0] font_rom [0:4095];
    initial $readmemh(FONT_FILE, font_rom);
    always @(posedge clk) row_bits <= font_rom[addr];
endmodule
