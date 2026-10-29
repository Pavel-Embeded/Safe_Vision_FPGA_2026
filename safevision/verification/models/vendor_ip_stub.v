


`timescale 1ns / 1ps


module sv_system_pll (
    input  wire refclk,
    input  wire reset,
    output wire extlock,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk2_out
);
    reg clkc = 1'b0;
    always #4 clkc = ~clkc;

    assign extlock  = 1'b1;
    assign clk0_out = clkc;
    assign clk1_out = clkc;
    assign clk2_out = clkc;
endmodule


module sdram (
    input  wire        Clk,
    input  wire        Clk_sft,
    input  wire        Rst,
    output wire        Sdr_init_done,
    output wire        Sdr_init_ref_vld,
    output wire        Sdr_busy,
    input  wire        App_wr_en,
    input  wire [20:0] App_wr_addr,
    input  wire [3:0]  App_wr_dm,
    input  wire [31:0] App_wr_din,
    input  wire        App_rd_en,
    input  wire [20:0] App_rd_addr,
    output wire        Sdr_rd_en,
    output wire [31:0] Sdr_rd_dout
);
    localparam integer RD_LAT = 4;

    reg [7:0] init_cnt = 8'd0;
    assign Sdr_init_done    = (init_cnt == 8'hFF);
    assign Sdr_init_ref_vld = 1'b0;
    assign Sdr_busy         = 1'b0;

    always @(posedge Clk) if (init_cnt != 8'hFF) init_cnt <= init_cnt + 8'd1;


    reg [31:0] mem [0:2_097_151];


    reg  [20:0] STUB_ERR_ADDR = 21'h1FFFFF;
    reg  [31:0] STUB_ERR_XOR  = 32'd0;


    always @(posedge Clk) if (App_wr_en) mem[App_wr_addr] <= App_wr_din;


    reg [20:0] addr_d [0:RD_LAT-1];
    reg        rd_d   [0:RD_LAT-1];
    integer i;
    always @(posedge Clk) begin
        addr_d[0] <= App_rd_addr;
        rd_d[0]   <= App_rd_en;
        for (i = 1; i < RD_LAT; i = i + 1) begin
            addr_d[i] <= addr_d[i-1];
            rd_d[i]   <= rd_d[i-1];
        end
    end

    assign Sdr_rd_en = rd_d[RD_LAT-1];

    wire [20:0] rd_a = addr_d[RD_LAT-1];
    assign Sdr_rd_dout = mem[rd_a] ^ ((rd_a == STUB_ERR_ADDR)  ?  STUB_ERR_XOR : 32'd0);


    wire unused = |{ App_wr_dm, Clk_sft, Rst };

endmodule

module sv_board_memory_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);
 reg sys=0;always #5 sys=~sys;
 reg mem=0;always #12.5 mem=~mem;
 assign clk0_out=sys;assign clk1_out=mem;assign #10 clk2_out=mem;assign extlock=1;
endmodule
