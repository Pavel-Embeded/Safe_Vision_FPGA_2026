`timescale 1ns/1ps
module tb_v3_audio_prefill_compare;
 reg[15:0] r=0;reg[9:0] w=0;reg p=0;wire[6:0] fill;
 v3_audio_prefill_compare #(.LIMIT(928)) a(r,w,p,fill[0]);
 v3_audio_prefill_compare #(.LIMIT(640)) b(r,w,p,fill[1]);
 v3_audio_prefill_compare #(.LIMIT(128)) c(r,w,p,fill[2]);
 v3_audio_prefill_compare #(.LIMIT(65536)) d(r,w,p,fill[3]);
 v3_audio_prefill_compare #(.LIMIT(65537)) e(r,w,p,fill[4]);
 v3_audio_prefill_compare #(.LIMIT(0)) f(r,w,p,fill[5]);
 v3_audio_prefill_compare #(.LIMIT(-1)) g(r,w,p,fill[6]);
 integer i,j,k,errors=0,comparisons=0;reg[31:0] total,rng=32'habc629ef;reg[6:0] expected;
 task probe(input[15:0] ring_value,input[9:0] words,input  partial);
 begin  partial = (partial === 1'b1); r=ring_value;w=words;p=partial;
  total={16'd0,ring_value}+(({22'd0,words}+2)/3)+partial;
  expected={total<32'hffffffff,total<32'd0,total<32'd65537,total<32'd65536,total<32'd128,total<32'd640,total<32'd928};
  #0.001;comparisons=comparisons+7;
  if(fill!==expected)begin errors=errors+1;if(errors<10)$display("[FAIL] prefill r=%0d words=%0d partial=%0d expected=%b actual=%b",r,w,p,expected,fill);end
   end endtask
 initial begin
  for(i=0;i<1024;i=i+1)for(j=0;j<1024;j=j+1)begin probe(i,j,0);probe(i,j,1);end
  for(i=65520;i<65536;i=i+1)for(j=0;j<1024;j=j+1)begin probe(i,j,0);probe(i,j,1);end
  for(i=0;i<16384;i=i+1)begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);probe(rng[15:0],rng[25:16],rng[26]);end
  if(errors==0)$display("[PASS] exact prefill word-budget comparator across seven parameter limits");
  $display("[TB] tb_v3_audio_prefill_compare done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] prefill oracle watchdog errors=1");$finish;end
endmodule
