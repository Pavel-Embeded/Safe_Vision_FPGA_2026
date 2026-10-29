


module sv_async_fifo #(parameter integer WIDTH=32, AW=9)(
 input wire rst,wr_clk,rd_clk,input wire [WIDTH-1:0] wr_data,
 input wire wr_valid,output wire wr_ready,output wire [AW-1:0] wr_level,
 output wire [WIDTH-1:0] rd_data,output wire rd_valid,input wire rd_ready,
 output wire [AW-1:0] rd_level);
 wire full,empty,af,ae,done,valid;
 assign wr_ready=done&&!full;assign rd_valid=valid&&!empty;
 a_pixel_fifo_ip #(.DATA_WIDTH_W(WIDTH),.DATA_WIDTH_R(WIDTH),
 .ADDR_WIDTH_W(AW),.ADDR_WIDTH_R(AW),.AL_FULL_NUM((1<<AW)-16),
 .AL_EMPTY_NUM(8),.SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")) u_fifo(
 .rst(rst),.clkw(wr_clk),.clkr(rd_clk),.we(wr_valid&&wr_ready),.di(wr_data),
 .re(rd_valid&&rd_ready),.dout(rd_data),.valid(valid),.full_flag(full),
 .empty_flag(empty),.afull(af),.aempty(ae),.wrusedw(wr_level),
 .rdusedw(rd_level),.wr_rst_done(done));
endmodule
