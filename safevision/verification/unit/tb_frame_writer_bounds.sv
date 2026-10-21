`timescale 1ns/1ps
module tb_frame_writer_bounds;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,start=0;reg [31:0] base=0;
    wire req,error,crc;integer checks=0;
    frame_writer dut(.clk(clk),.rst_n(rst_n),.start(start),.slot_sel(2'd0),.slot_base(base),
      .din(16'd0),.din_valid(1'b0),.din_ready(),.wr_req(req),.wr_addr(),.wr_data(),.wr_len(),
      .wr_ready(1'b0),.wr_done(),.slot_valid(),.crc_ok(crc),.crc_value(),.px_cnt(),
      .wr_error(error),.err_code(),.err_detail());
    task reject(input [31:0] address);
      @(negedge clk);rst_n=0;repeat(3)@(negedge clk);
      base=address;rst_n=1;@(negedge clk);start=1;@(negedge clk);start=0;
      repeat(3)@(negedge clk);
      if(!error || req || crc)$fatal(1,"illegal address admitted: %h",address);
      checks=checks+1;$display("[PASS] rejected base=%h",address);
    endtask
    initial begin
      reject(32'hffff_fffc);reject(32'hfff6_0000);reject(32'h0040_0000);
      reject(32'h0036_0004);reject(32'h0000_0001);
      $display("PASS tb_frame_writer_bounds: checks=%0d",checks);$finish;
    end
endmodule
