`timescale 1ns/1ps
module tb_v3_hud_palette192;
 reg clk=0,rst=0,on=0,valid=0;always #5 clk=~clk;
 reg[15:0]fg=0,bg=0;wire[15:0]pixel;wire ov;
 v3_hud_palette224 dut(clk,rst,valid,on,fg,bg,pixel,ov);
 function[15:0]reference(input[15:0]f,b,input bit en);integer r,g,bl,a;begin a=en?224:0;
 r=(f[15:11]*a+b[15:11]*(255-a)+127)/255;g=(f[10:5]*a+b[10:5]*(255-a)+127)/255;bl=(f[4:0]*a+b[4:0]*(255-a)+127)/255;
 reference={5'(r),6'(g),5'(bl)};end endfunction
 function[15:0]colour(input integer c);begin case(c)0:colour=16'hffff;1:colour=16'h07e0;2:colour=16'h7bef;3:colour=16'h05bf;4:colour=16'hffe0;5:colour=16'hf800;default:colour=0;endcase end endfunction
 reg[15:0]q[0:2];reg[2:0]vq=0;integer errors=0,comparisons=0,i,c,b,m;
 always@(posedge clk)begin
 if(!rst)begin for(i=0;i<3;i++)q[i]=0;vq=0;end
 else begin for(i=2;i>0;i--)q[i]=q[i-1];q[0]=reference(fg,bg,on);vq={vq[1:0],valid};#0.001;comparisons+=2;
 if(pixel!==q[2]||ov!==vq[2])begin errors++;if(errors<8)$display("[FAIL] palette fg=%h bg=%h on=%b got=%h want=%h valid=%b/%b",fg,bg,on,pixel,q[2],ov,vq[2]);end end
 end
 initial begin repeat(5)@(negedge clk);rst=1;
 for(c=0;c<7;c++)for(m=0;m<2;m++)for(b=0;b<65536;b++)begin
 @(negedge clk);fg=colour(c);bg=b;on=m;valid=b%7!=2;
 if(c==3&&m==1&&b==32768)begin #1;rst=0;repeat(3)@(negedge clk);rst=1;end
 end
 repeat(4)@(negedge clk);if(!errors)$display("[PASS] all65536 RGB565 backgrounds,all7 production colours,alpha0/224,invalid bubbles,three clocks and async resets;independent rounded arithmetic");
 $display("[TB] tb_v3_hud_palette192 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #20000000;$display("[FAIL] HUD palette watchdog errors=1");$finish;end
endmodule
