`timescale 1ns/1ps
module tb_v3_source_wait_writer;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,start=0,valid=0,hint=0,ack=1;reg[15:0] din=0;
 wire ready,req,done,error;wire[3:0] slots;wire[18:0] pixels;
 integer errors=0,comparisons=0,guard=0;
 frame_writer #(.FRAME_WIDTH(8),.FRAME_HEIGHT(4),.PIX_PER_FRAME(32),.GAP_TIMEOUT(16),.SOURCE_PROGRESS_AWARE(1)) dut(
  .clk(clk),.rst_n(rst),.start(start),.slot_sel(2'd0),.slot_base(32'd0),.din(din),.din_valid(valid),.din_ready(ready),
  .wr_req(req),.wr_addr(),.wr_data(),.wr_len(),.wr_ready(ack),.wr_done(done),.slot_valid(slots),.crc_ok(),.crc_value(),
  .px_cnt(pixels),.wr_error(error),.err_code(),.err_detail(),.source_progress(hint));
 task ck(input  good,input [4095:0] why);begin begin good = (good === 1'b1); comparisons = comparisons + 1;if(!good)begin errors = errors + 1;$display("[FAIL] %s",why);end end  end endtask
 task fresh;begin begin
  @(negedge clk);rst=0;start=0;valid=0;hint=0;ack=1;repeat(4)@(negedge clk);rst=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
 end  end endtask
 task pixel(input[15:0] value);begin begin
  @(negedge clk);valid=1;din=value;@(posedge clk);
  while(!ready)@(posedge clk);
  @(negedge clk);valid=0;
 end  end endtask
 initial begin
  fresh();hint=1;repeat(64)@(negedge clk);
  ck(!error&&pixels==0&&!done&&slots==0,"source-only credit extends a wait without accepting or publishing pixels");
  hint=0;guard=0;while(!error&&guard<24)begin @(negedge clk);guard = guard + 1;end
  ck(error&&!done&&slots==0,"the writer expires when source events stop");
  fresh();hint=1;ack=0;pixel(16'h1256);pixel(16'habcd);
  ck(req&&pixels==2,"a real packed word is pending on the memory bus");
  guard=0;while(!error&&guard<24)begin @(negedge clk);guard = guard + 1;end
  ck(error&&!done&&slots==0,"raw source credit cannot reset a pending write deadline");
  fresh();guard=0;while(dut.gap_cnt<16&&!error&&guard<20)begin @(negedge clk);guard = guard + 1;end
  ck(dut.gap_cnt==16&&!error,"the original writer counter reaches its deadline");
  hint=1;@(posedge clk);#1;
  ck(!error&&dut.gap_cnt==0,"a qualified writer credit on the deadline edge wins");
  @(negedge clk);rst=0;
  $display("[PASS] empty-source credit, stopped source, pending write protection and exact deadline priority");
  $display("PASS tb_v3_source_wait_writer errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
