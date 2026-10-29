`timescale 1ns/1ps
module tb_v3_related_status_capture;
 reg sys_clk=0,ref_clk=0,mem_clk=0,rst_n=0;
 always #5 sys_clk=~sys_clk;
 initial begin #5;forever #10 ref_clk=~ref_clk;end

 initial begin #3;forever #10 mem_clk=~mem_clk;end
 reg[203:0] ref_source=0;reg[47:0] mem_source=0;
 wire[203:0] ref_data;wire[47:0] mem_data;wire ref_valid,mem_valid;
 v3_related_status_capture #(.WIDTH(204)) a(.clk(sys_clk),.rst_n(rst_n),.source_data(ref_source),.data(ref_data),.valid(ref_valid));
 v3_related_status_capture #(.WIDTH(48)) b(.clk(sys_clk),.rst_n(rst_n),.source_data(mem_source),.data(mem_data),.valid(mem_valid));
 integer errors=0,comparisons=0,i;reg[31:0] epoch=32'h92a13fcb;
 always @(posedge ref_clk)if(rst_n)begin
  epoch<=epoch+32'h6d2b79f5;
  ref_source<={epoch[11:0],epoch^32'hffffffff,epoch+32'hca621c5d,epoch-32'h57c3ef8b,~epoch,epoch^32'h8314bca5,epoch};
 end else begin epoch<=32'h92a13fcb;ref_source<=0;end
 always @(posedge mem_clk)if(rst_n)mem_source<={epoch[15:0],~epoch};else mem_source<=0;
 reg[203:0] ref_expected;reg[47:0] mem_expected;
 always @(posedge sys_clk)begin
  ref_expected=ref_source;mem_expected=mem_source;
  #1;
  comparisons=comparisons+1;
  if(rst_n)begin
   if(!ref_valid || !mem_valid || ref_data!==ref_expected || mem_data!==mem_expected)begin
    errors=errors+1;if(errors<9)$display("[FAIL] coherent full252-bit registered snapshot");end
  end else if(ref_valid || mem_valid || ref_data!==0 || mem_data!==0)begin
   errors=errors+1;$display("[FAIL] reset clears payload and validity");end
 end
 initial begin

  #1;rst_n=1;#1;rst_n=0;
  for(i=0;i<16;i=i+1)begin
   #37;@(negedge sys_clk);rst_n=1;
   repeat(257+i)@(negedge sys_clk);
   #2;rst_n=0;#1;
   comparisons=comparisons+1;
   if(ref_valid || mem_valid || ref_data!==0 || mem_data!==0)begin
    errors=errors+1;$display("[FAIL] asynchronous epoch assertion suppresses old status");end
  end
  repeat(4)@(negedge sys_clk);
  if(errors==0)$display("[PASS] complete snapshots, source carries, coincident/different phases and16reset epochs");
  $display("[TB] tb_v3_related_status_capture done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #100000;$display("[FAIL] related status watchdog errors=1");$finish;end
endmodule
