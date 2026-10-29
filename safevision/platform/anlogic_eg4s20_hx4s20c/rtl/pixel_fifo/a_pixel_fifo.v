


module a_pixel_fifo #(parameter integer AW=10)(
    input wire rst,wr_clk,rd_clk,
    input wire [31:0] wr_data,input wire wr_en,output wire full,almost_full,
    output wire [AW-1:0] wr_words,output wire wr_ready,
    input wire rd_en,output wire [15:0] rd_data,output wire rd_valid,empty,almost_empty,
    output wire [AW:0] rd_pixels
);
    wire wr_reset_done;
    assign wr_ready=wr_reset_done&&!full&&!rst;
    a_pixel_fifo_ip #(.DATA_WIDTH_W(32),.DATA_WIDTH_R(16),.ADDR_WIDTH_W(AW),
      .ADDR_WIDTH_R(AW+1),.AL_FULL_NUM((1<<AW)-24),.AL_EMPTY_NUM(32),
      .SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")) fifo(
      .rst(rst),.clkw(wr_clk),.clkr(rd_clk),.we(wr_en&&wr_ready),.di(wr_data),
      .re(rd_en&&!empty),.dout(rd_data),.valid(rd_valid),.full_flag(full),
      .empty_flag(empty),.afull(almost_full),.aempty(almost_empty),
      .wrusedw(wr_words),.rdusedw(rd_pixels),.wr_rst_done(wr_reset_done));
    // synthesis translate_off
    initial if(AW<6||AW>14)begin $display("[FAIL] a_pixel_fifo AW must be 6..14"); $finish; end 
    // synthesis translate_on
endmodule
