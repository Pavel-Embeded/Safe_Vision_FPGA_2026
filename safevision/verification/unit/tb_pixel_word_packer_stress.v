`timescale 1ns/1ps
module tb_pixel_word_packer_stress;
 reg clk=0,rst_n=0,valid=0,word_ready=0;always #7 clk=~clk;
 reg [15:0] pixel=0;wire ready,word_valid,pending;wire [31:0] word_data;
 pixel_word_packer dut(.clk(clk),.rst_n(rst_n),.pixel(pixel),.valid(valid),.ready(ready),
  .word_data(word_data),.word_valid(word_valid),.word_ready(word_ready),.pending(pending));
 integer sent=0,received=0,checks=0,goal=2049,seed=32'h517123,stalls=0;
 reg source_fire=0,stalled=0;reg [31:0] held;
 function [15:0] value(input integer n);begin value=v_cast_u16((n*97)^(n<<7)^16'had32); end endfunction
 always @(posedge clk)begin
  source_fire<=rst_n&&valid&&ready;
  if(!rst_n)begin sent=0;received=0;stalled=0;end
  else begin
   if(stalled&&(!word_valid||word_data!==held))begin $display("[FAIL] packer changed held output"); $finish; end 
   stalled=word_valid&&!word_ready;held=word_data;if(stalled)stalls=stalls+1;
   if(word_valid&&word_ready)begin
    if(word_data!=={value(2*received+1),value(2*received)})
     begin $display("[FAIL] packer order/halfword received=%0d data=%h",received,word_data); $finish; end 
    received=received+1;checks=checks+1;
   end
   if(valid&&ready)begin
    if(pixel!==value(sent))begin $display("[FAIL] source ordering"); $finish; end sent=sent+1;
   end
  end
 end
 always @(negedge clk)begin
  if(!rst_n)begin valid=0;word_ready=0;end
  else begin
   word_ready=($random(seed)&7)<3;
   if(!valid||source_fire)begin valid=(sent<goal)&&(($random(seed)&7)<6);pixel=value(sent);end
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  wait(sent==goal&&received==goal/2);repeat(20)@(negedge clk);
  if(!pending||word_valid)begin $display("[FAIL] odd final pixel was not held"); $finish; end 
  #2.137;rst_n=0;#0.1;if(pending||word_valid||ready)begin $display("[FAIL] asynchronous reset did not flush odd pixel"); $finish; end 
  repeat(4)@(negedge clk);goal=2002;rst_n=1;
  wait(sent==goal&&received==goal/2);repeat(20)@(negedge clk);
  if(pending||word_valid||checks!=2025||stalls<100)begin $display("[FAIL] packer coverage checks=%0d stalls=%0d pending=%b",checks,stalls,pending); $finish; end 
  $display("PASS tb_pixel_word_packer_stress: 2025 independently ordered words, stalls=%0d, odd pending pixel flush and fresh epoch",stalls);$finish;
 end
 initial begin #500000;begin $display("[FAIL] packer watchdog"); $finish; end end

function [15:0] v_cast_u16; input [15:0] value; begin begin v_cast_u16=value; end  end endfunction
endmodule
