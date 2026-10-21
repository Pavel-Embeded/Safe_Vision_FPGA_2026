`timescale 1ns/1ps
module tb_v3_waveform193;
 reg clk=0,rst=0,fs=0,pv=0,de=0;reg[23:0] pcm=0;reg[11:0] x=0,y=0;always #5 clk=~clk;
 wire tr,grid,ready;integer errors=0,comparisons=0,i,j,k,a,b,ya,yb,pat;integer values[0:255];
 v3_pcm_waveform dut(clk,rst,fs,pv,pcm,x,y,de,tr,grid,ready);
 task ck(input bit ok,input string m);begin comparisons++;if(!ok)begin errors++;if(errors<8)$display("[FAIL] %s",m);end end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(pat=0;pat<6;pat++)begin
   for(i=0;i<128;i++)begin
    case(pat)0:values[i]=0;1:values[i]=(i%32<16)?127:-128;2:values[i]=i-128;
     3:values[i]=(i==128)?127:0;4:values[i]=$rtoi(120*$sin(i*6.28318530718/24));default:values[i]=(i*73%256)-128;endcase
    @(negedge clk);pv=1;pcm={8'(values[i]),16'd0};@(negedge clk);pv=0;
    if(i%13==0)repeat(2)@(negedge clk);
   end
   ck(dut.pending,"complete capture held until vblank");
   for(i=0;i<9;i++)begin @(negedge clk);pv=1;pcm=24'h7f0000;end
   @(negedge clk);pv=0;fs=1;@(negedge clk);fs=0;ck(ready,"first complete bank published");
   for(i=0;i<256;i++)begin
    a=values[i/2==0?0:i/2-1];b=values[i/2];ya=384-(a>>>2);yb=384-(b>>>2);
    for(j=350;j<418;j++)begin @(negedge clk);de=1;x=368+i;y=j;@(posedge clk);#1;
     ck(tr===((j>=(ya<yb?ya:yb))&&(j<=(ya>yb?ya:yb))),"PCM connected trace exact signed height");
     ck(grid===((j==384)||(j==350)||(j==417)||(i==0)||(i==255)),"scope grid aligned to sample read");
    end
   end
   @(negedge clk);de=0;@(posedge clk);#1;ck(!tr&&!grid,"blanking never draws");
  end
  @(negedge clk);rst=0;@(posedge clk);#1;ck(!ready&&!tr,"reset hides uncleared RAM");
  if(!errors)$display("[PASS] silence,square,ramp,impulse,sine,random;exact128 samples,2columns/sample;vblank atomic banks;blanking/reset");
  $display("[TB] tb_v3_waveform193 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] waveform watchdog errors=1");$finish;end
endmodule
