

`timescale 1ns/1ps
`include "safevision_defs.vh"
module writer_crc_case #(parameter integer STRIDE=1)(output reg done=0);
 localparam P=4096,W=64,H=64;
 reg clk=0,rst_n=0,start=0,valid=0,ready=0,fast=1;
 always #4 clk=~clk;
 reg [15:0] din=0;reg [1:0] slot=0;reg [31:0] base=0;
 wire din_ready,wr_req,wr_done,crc_ok,wr_error;
 wire [31:0] wr_addr,wr_data;wire [15:0] wr_len,crc_value;
 wire [3:0] slot_valid;wire [18:0] px_cnt;wire [7:0] ec,ed;
 frame_writer #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.PIX_PER_FRAME(P),
  .SAMPLE_STRIDE(STRIDE),.GAP_TIMEOUT(64)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.slot_sel(slot),.slot_base(base),
  .din(din),.din_valid(valid),.din_ready(din_ready),.wr_req(wr_req),
  .wr_addr(wr_addr),.wr_data(wr_data),.wr_len(wr_len),.wr_ready(ready),
  .wr_done(wr_done),.slot_valid(slot_valid),.crc_ok(crc_ok),.crc_value(crc_value),
  .px_cnt(px_cnt),.wr_error(wr_error),.err_code(ec),.err_detail(ed));
 integer cycle=0,last_capture=-100,updates=0,min_gap=100000,words=0;
 reg score=0;reg [15:0] seed=16'h73a5,golden_crc=0;
 function automatic [15:0] pixel(input integer n);
  pixel=(n*19)^(n>>3)^seed;
 endfunction
 function automatic [15:0] crc_word(input [15:0] prior,input [31:0] data);
  reg [15:0] c;integer bitno;
  begin c=prior;for(bitno=31;bitno>=0;bitno=bitno-1)
   c=(c<<1)^((c[15]^data[bitno])?16'h1021:16'd0);
   crc_word=c;
  end
 endfunction
 always @(negedge clk)ready=rst_n&&(fast||(cycle%7>=3));
 always @(posedge clk)begin
  cycle=cycle+1;
  if(!rst_n)last_capture=-100;
  else begin
   if(dut.crc_src_pend!==0&&dut.crc_src_pend!==1)$fatal(1,"unknown CRC enable");

   if(dut.crc_src_pend&&!(dut.state==0&&start))begin
    if(cycle-last_capture<2)$fatal(1,"CRC feedback captured on adjacent edges");
    if(last_capture>=0&&cycle-last_capture<min_gap)min_gap=cycle-last_capture;
    last_capture=cycle;updates=updates+1;
   end
   if(score&&wr_req&&ready)begin
    if(wr_len!==1||wr_addr!==base+words*4||
       wr_data!=={pixel(words*2+1),pixel(words*2)})$fatal(1,"write oracle stride=%0d word=%0d",STRIDE,words);
    if(words%STRIDE==0)golden_crc=crc_word(golden_crc,wr_data);
    words=words+1;
   end
  end
 end
 task begin_frame;
  begin @(negedge clk);start=1;
   @(negedge clk);start=0;
  end
 endtask
 task send_pixels(input integer count);
  integer n;reg take;
  begin n=0;while(n<count)begin
   @(negedge clk);valid=1;din=pixel(n);
   @(posedge clk);take=valid&&din_ready;
   #0.2;if(take)n=n+1;
  end
  @(negedge clk);valid=0;
  end
 endtask
 task full_frame;
  begin words=0;golden_crc=0;score=1;
   begin_frame;send_pixels(P);wait(wr_done===1);#0.2;
   if(words!=P/2||crc_ok!==1||crc_value!==golden_crc||
      wr_error!==0||px_cnt!==P||slot_valid[slot]!==1)
    $fatal(1,"frame/CRC oracle stride=%0d",STRIDE);
   score=0;repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  full_frame;

  score=0;begin_frame;send_pixels(2);
  if(dut.crc_src_pend!==1)$fatal(1,"pending reset coverage");
  rst_n=0;#0.2;
  if(dut.crc_src_pend!==0||dut.crc_src!==0)$fatal(1,"pending CRC not reset");
  repeat(3)@(negedge clk);rst_n=1;
  slot=1;base=`SV_IMG1_BASE;seed=16'ha65c;fast=0;
  full_frame;
  if(updates<2*((P/2+STRIDE-1)/STRIDE))$fatal(1,"CRC update coverage");
  if(STRIDE==1&&min_gap!=3)$fatal(1,"fastest pair cadence not exercised: %0d",min_gap);
  $display("[PASS] CRC feedback stride=%0d updates=%0d min_capture_gap=%0d data/write/CRC/reset",STRIDE,updates,min_gap);
  done=1;
 end
endmodule
module tb_frame_writer_crc_feedback;
 wire [2:0] done;
 writer_crc_case #(.STRIDE(1)) a(done[0]);
 writer_crc_case #(.STRIDE(2)) b(done[1]);
 writer_crc_case #(.STRIDE(1024)) c(done[2]);
 initial begin wait(&done);$display("[PASS] CRC FEEDBACK enable contract");$finish;end
 initial begin #200000;$fatal(1,"CRC feedback watchdog");end
endmodule
