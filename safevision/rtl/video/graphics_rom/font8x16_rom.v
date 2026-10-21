// One synchronous read stage; no reset on ROM/output to allow BRAM inference.
// Caller masks stale startup data until its metadata pipeline is valid.
// TD resolves this default relative to this source file. Simulation TBs pass
// "font8x16.mem" explicitly and the runner copies the asset into each run dir.
module font8x16_rom #(parameter FONT_FILE="../../../assets/fonts/font8x16.mem")(
    input wire clk, input wire [11:0] addr, output reg [7:0] row_bits);
    reg [7:0] font_rom [0:4095];
    initial $readmemh(FONT_FILE, font_rom);
    always @(posedge clk) row_bits <= font_rom[addr];
endmodule
