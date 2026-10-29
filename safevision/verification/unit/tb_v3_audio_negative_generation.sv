`timescale 1ns/1ps
module tb_v3_audio_negative_generation;
 integer negative_errors=0;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [127:0] in_data=0;reg [3:0] in_valid=0;wire [3:0] in_ready;
 reg cv=0;reg [1:0] cs=0;reg [7:0] cg=1;wire cr;
 wire [3:0] pre;wire [63:0] levels;wire [39:0] out;wire ov;reg ore=1;
 wire req,wr;wire [31:0] addr,wd;wire [15:0] len;reg ack=0,busy=0,rv=0;reg [31:0] rd=0;
 reg [31:0] ram[0:65535];reg [31:0] lataddr,latdata;reg latwr;integer delay=0,cycle=0;
 integer sent[0:3],got[0:3],checks=0;integer i;reg [1:0] active=0;
 reg stalled=0;reg [39:0] held_output=0;
 v3_pcm_ring #(.PTR_W(5),.PREFETCH(8)) d(.clk(clk),.rst_n(rst_n),.in_data(in_data),.in_valid(in_valid),.in_ready(in_ready),
 .commit_valid(cv),.commit_slot(cs),.commit_generation(cg),.commit_ready(cr),.fallback(4'b0),.prefetched(pre),.levels(levels),
 .out_data(out),.out_valid(ov),.out_ready(ore),.output_level(10'd0),.req(req),.wr(wr),.addr(addr),.wdata(wd),.len(len),
 .ack(ack),.busy(busy),.rdata(rd),.rvalid(rv));

 always @(posedge clk)begin
  ack<=0;rv<=0;cycle<=cycle+1;
  if(rst_n)begin
   if(stalled&&(!ov||out!==held_output))$fatal(1,"ring output changed during backpressure");
   stalled<=ov&&!ore;held_output<=out;
   if(!busy&&req&&cycle%11!=0&&cycle%7!=0)begin
    ack<=1;busy<=1;lataddr<=addr;latdata<=wd;latwr<=wr;delay<=2+cycle%9;
    if(len!=1||addr<32'h280000||addr>=32'h2c0000||addr[1:0]!=0)$fatal(1,"ring address/len");
   end else if(busy)begin
    if(delay!=0)delay<=delay-1;
    else begin busy<=0;if(latwr)ram[(lataddr-32'h280000)>>2]<=latdata;
      else begin rd<=ram[(lataddr-32'h280000)>>2];rv<=1;end
    end
   end
   for(i=0;i<4;i=i+1)if(in_valid[i]&&in_ready[i])sent[i]<=sent[i]+1;
   if(ov&&ore)begin
    if(out[39:32]!==cg)begin negative_errors=negative_errors+1;if(negative_errors<=3)$display("[FAIL AUDIO_GENERATION] generation got=%0d expected=%0d",out[39:32],cg);end
    if(out[31:0]!=={16'(active),16'(got[active])})$fatal(1,"ring order slot=%0d got=%h idx=%0d",active,out,got[active]);
    got[active]<=got[active]+1;checks<=checks+1;
   end
  end else stalled<=0;
 end
 always @(negedge clk)if(rst_n)begin
  for(integer j=0;j<4;j=j+1)begin in_data[j*32+:32]={16'(j),16'(sent[j])};in_valid[j]=(sent[j]<220);end


  ore=ov&&(cycle%13!=0)&&(cycle%9!=0);
 end
 task commit(input [1:0] s,input [7:0] g);
  begin wait(!ov&&cr&&!busy);@(negedge clk);cs=s;cg=g;active=s;cv=1;@(negedge clk);cv=0;end
 endtask
 initial begin
  for(i=0;i<4;i=i+1)begin sent[i]=0;got[i]=0;end
  #30;rst_n=1;wait(&pre);commit(0,1);wait(got[0]>=120);commit(3,2);
  wait(got[3]>=120);commit(1,3);wait(got[1]>=120);commit(2,4);wait(got[2]>=120);
  if(checks<480)$fatal(1,"ring coverage");
  rst_n=0;in_valid=0;#30;for(i=0;i<4;i=i+1)begin sent[i]=0;got[i]=0;in_data[i*32+:32]={16'(i),16'(0)};end
  rst_n=1;wait(&pre);commit(0,5);wait(got[0]>=60);
  $display("[PASS] ring wrap/order/backpressure/refresh/4slots/generation/reset checks=%0d",checks);
  $display("PASS tb_v3_audio_negative_generation errors=%0d comparisons=%0d",negative_errors,checks);$finish;
 end
 initial begin #2000000;$fatal(1,"ring watchdog");end
endmodule
