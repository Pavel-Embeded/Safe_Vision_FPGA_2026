`timescale 1ns/1ps
module priority_difference_case #(parameter integer N=240,COMPARE_OLD=1)(output reg done=0,output integer errors=0,comparisons=0);
 reg clk=0;always #5 clk=~clk;reg rst_n=0,sample_valid=0,alarm_req=0;
 reg[23:0] wl=0,wr=0,tl=0,tr=0;wire[23:0] ol,orr,rl,rr;wire ov,rv;wire[8:0] gain,rg;
 audio_priority_arbiter #(.RAMP_N(N)) dut(clk,rst_n,sample_valid,alarm_req,wl,wr,tl,tr,ol,orr,ov,gain);
 audio_priority_arbiter_reference #(.RAMP_N(N)) reference(clk,rst_n,sample_valid,alarm_req,wl,wr,tl,tr,rl,rr,rv,rg);
 integer step,g=0,remainder=0,next_gain,i;reg[31:0] seed=32'h7195aa23+N;
 reg[23:0] expected_l,expected_r;reg expected_valid;
 reg signed[63:0] wide_l,wide_r,swl,swr,stl,str;
 task ck;input condition;input[511:0] label_text;begin
  comparisons=comparisons+1;
  if(!condition)begin errors=errors+1;if(errors<8)$display("[FAIL] N=%0d %s gain=%0d/%0d l=%h/%h r=%h/%h",N,label_text,gain,g,ol,expected_l,orr,expected_r);end
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin g=0;remainder=0;expected_l=0;expected_r=0;expected_valid=0;end
  else begin
   expected_valid=sample_valid;
   if(sample_valid)begin
    step=(remainder+256)/N;remainder=(remainder+256)%N;
    if(alarm_req)begin next_gain=g+step;if(next_gain>256)next_gain=256;end
    else begin next_gain=g-step;if(next_gain<0)next_gain=0;end
    g=next_gain;
    swl=$signed(wl);swr=$signed(wr);stl=$signed(tl);str=$signed(tr);
    wide_l=swl*(256-g)+stl*g;wide_r=swr*(256-g)+str*g;
    expected_l=(wide_l>>>8);expected_r=(wide_r>>>8);
   end
  end
  #1;
  ck(ov===expected_valid&&gain===g&&ol===expected_l&&orr===expected_r,
     "independent signed 64bit convex mixture, full-range saturation and valid timing");
  if(COMPARE_OLD)ck(ov===rv&&gain===rg&&ol===rl&&orr===rr,"original implementation cycle-exact equivalence");
 end
 task random_word;output[23:0] value;begin
  seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);value=seed[23:0];
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(i=0;i<120000;i=i+1)begin
   random_word(wl);random_word(wr);random_word(tl);random_word(tr);
   case(i%11)
    0:begin wl=24'h800000;wr=24'h7fffff;tl=24'h7fffff;tr=24'h800000;end
    1:begin wl=24'h7fffff;wr=24'h800000;tl=24'h800000;tr=24'h7fffff;end
    2:begin wl=0;wr=0;tl=24'hffffff;tr=1;end
    default:;
   endcase
   sample_valid=i%7!=0;alarm_req=(i/1500)%2;
   if(i%21003==0)rst_n=0;else rst_n=1;
   @(negedge clk);
  end
  sample_valid=0;repeat(4)@(negedge clk);done=1;
 end
endmodule
module tb_v3_priority_difference;
 wire[2:0] done;wire[31:0] e0,e1,e2,c0,c1,c2;
 priority_difference_case #(.N(240)) normal_case(done[0],e0,c0);
 priority_difference_case #(.N(1),.COMPARE_OLD(0)) single_tick_case(done[1],e1,c1);
 priority_difference_case #(.N(1025)) wide_remainder_case(done[2],e2,c2);
 initial begin wait(&done);#2;
  if(e0+e1+e2==0)$display("[PASS] exact two-product priority blend and bounded fractional ramp");
  $display("[TB] tb_v3_priority_difference done errors=%0d comparisons=%0d",e0+e1+e2,c0+c1+c2);$finish;
 end
 initial begin #2000000;$display("[FAIL] priority oracle timeout errors=1");$finish;end
endmodule
