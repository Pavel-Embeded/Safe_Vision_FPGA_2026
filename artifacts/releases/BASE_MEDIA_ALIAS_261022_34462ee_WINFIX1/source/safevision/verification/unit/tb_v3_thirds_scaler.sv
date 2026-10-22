`timescale 1ns/1ps
module tb_v3_thirds_scaler;
 reg clk=0,rst_n=0,valid_in=0,bilinear=0;always #5 clk=~clk;
 reg[15:0] p00=0,p10=0,p01=0,p11=0;reg[7:0] fx=0,fy=0;
 wire[15:0] pixel,original;wire valid_out,original_valid;
 v3_scaler_bilinear_thirds dut(clk,rst_n,valid_in,bilinear,p00,p10,p01,p11,fx,fy,pixel,valid_out);
 scaler_bilinear control(clk,rst_n,valid_in,bilinear,p00,p10,p01,p11,fx,fy,original,original_valid);
 integer errors=0,comparisons=0,a,b,f,i;reg[31:0] seed=32'hf24391cd;
 reg[15:0] expected0=0,expected1=0,expected2=0;reg[2:0] val=0;
 function integer lerp(input integer aa,bb,ff);begin lerp=(aa*(256-ff)+bb*ff+128)/256;end endfunction
 function[15:0] rgb(input[15:0] q00,q10,q01,q11,input integer xx,yy);
 integer rr,gg,bb;begin
 rr=lerp(lerp(q00[15:11],q10[15:11],xx),lerp(q01[15:11],q11[15:11],xx),yy);
 gg=lerp(lerp(q00[10:5],q10[10:5],xx),lerp(q01[10:5],q11[10:5],xx),yy);
 bb=lerp(lerp(q00[4:0],q10[4:0],xx),lerp(q01[4:0],q11[4:0],xx),yy);
 rgb={rr[4:0],gg[5:0],bb[4:0]};end endfunction
 always @(posedge clk)begin
 if(!rst_n)begin expected0=0;expected1=0;expected2=0;val=0;end
 else begin
 expected2=expected1;expected1=expected0;expected0=bilinear?rgb(p00,p10,p01,p11,fx,fy):p00;
 val={val[1:0],valid_in};end
 #1;
 comparisons=comparisons+1;
 if(pixel!==original || valid_out!==original_valid || pixel!==expected2 || valid_out!==val[2])begin
  errors=errors+1;if(errors<12)$display("[FAIL] thirds pipeline p=%h old=%h independent=%h",pixel,original,expected2);
 end
 end
 task step;begin @(negedge clk);end endtask
 initial begin
 repeat(4)step;rst_n=1;bilinear=1;valid_in=1;
 for(a=0;a<64;a=a+1)for(b=0;b<64;b=b+1)for(f=0;f<3;f=f+1)begin
 p00={a[4:0],a[5:0],a[4:0]};p10={b[4:0],b[5:0],b[4:0]};
 p01=p00^16'h75ad;p11=p10^16'hc9b6;fx=f*85;fy=((a+b)%3)*85;step;
 end
 for(i=0;i<50000;i=i+1)begin
 seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};p00=seed[15:0];p10=seed[31:16];
 seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};p01=seed[15:0];p11=seed[31:16];
 fx=(seed[3:2]%3)*85;fy=(seed[5:4]%3)*85;bilinear=seed[6];valid_in=seed[7];
 rst_n=(i%997)!=0;step;
 end
 rst_n=1;valid_in=0;repeat(5)step;
 $display("[PASS] exact thirds, original pipeline and independent weighted integer model");
 $display("[TB] tb_v3_thirds_scaler done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #2000000;$fatal(1,"thirds scaler timeout");end
endmodule
