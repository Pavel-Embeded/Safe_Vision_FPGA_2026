`timescale 1ns/1ps
module tb_v3_video_thirds;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,bilinear=1;reg[15:0] p00=0,p10=0,p01=0,p11=0;
 reg[7:0] fx=0,fy=0;wire[15:0] result;wire result_valid;
 scaler_bilinear #(.RASTER_THIRDS(1)) dut(clk,rst,valid,bilinear,p00,p10,p01,p11,fx,fy,result,result_valid);
 function integer interpolate(input integer a,b,f);begin begin interpolate=(a*(256-f)+b*f+128)/256;end  end endfunction
 function[15:0] golden(input[15:0] a,b,c,d,input integer x,y,input  mode);
  integer rr,gg,bb;begin begin
   mode = (mode === 1'b1); rr=interpolate(interpolate(a[15:11],b[15:11],x),interpolate(c[15:11],d[15:11],x),y);
   gg=interpolate(interpolate(a[10:5],b[10:5],x),interpolate(c[10:5],d[10:5],x),y);
   bb=interpolate(interpolate(a[4:0],b[4:0],x),interpolate(c[4:0],d[4:0],x),y);
   golden=mode ? {v_cast_s5(rr),v_cast_s6(gg),v_cast_s5(bb)}:a;
  end
  end endfunction
 function[15:0] color(input integer n);begin begin color={v_cast_s5(n%32),v_cast_s6(n),v_cast_s5((n*13)%32)};end  end endfunction
 function[7:0] fraction(input integer n);begin begin fraction=n==0 ? 0:n==1 ? 85:170;end  end endfunction
 reg[15:0] expected0,expected1,expected2;reg v0=0,v1=0,v2=0;
 integer comparisons=0,errors=0;
 always @(posedge clk)begin
  if(!rst)begin expected0=0;expected1=0;expected2=0;v0=0;v1=0;v2=0;end
  else begin expected2=expected1;expected1=expected0;expected0=golden(p00,p10,p01,p11,fx,fy,bilinear);
   v2=v1;v1=v0;v0=valid;#1;
   if(result_valid!==v2)begin errors=errors+1;if(errors<8)$display("[FAIL] valid latency");end
   if(result!==expected2)begin errors=errors+1;if(errors<8)$display("[FAIL] exact thirds expected=%h actual=%h",expected2,result);end
   comparisons=comparisons+1;
  end
 end
 integer a,b,f,i;reg[31:0] random_state=32'h7195bc23;
 task next_random;begin begin random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};end  end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(a=0;a<64;a=a+1)for(b=0;b<64;b=b+1)for(f=0;f<3;f=f+1)begin
   valid=1;bilinear=1;p00=color(a);p10=color(b);p01=color(63-b);p11=color(63-a);fx=fraction(f);fy=0;
   @(negedge clk);
   p00=color(a);p10=color(a);p01=color(b);p11=color(b);fx=0;fy=fraction(f);@(negedge clk);
  end
  for(i=0;i<100000;i=i+1)begin
   next_random();p00=random_state[15:0];next_random();p10=random_state[15:0];
   next_random();p01=random_state[15:0];next_random();p11=random_state[15:0];
   fx=fraction(i%3);fy=fraction((i/3)%3);valid=i%7!=0;bilinear=i%11!=0;
   @(negedge clk);
  end
  valid=0;repeat(4)@(negedge clk);
  rst=0;repeat(2)@(negedge clk);rst=1;
  valid=1;p00=16'hffff;p10=0;p01=0;p11=16'hffff;fx=85;fy=170;
  repeat(5)@(negedge clk);valid=0;repeat(4)@(negedge clk);
  if(errors==0)$display("[PASS] exhaustive two-neighbor scalar fractions and 100000 four-neighbor exact randomized vectors");
  $display("[TB] tb_v3_video_thirds done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #10000000;$display("[FAIL] timeout errors=1");$finish;end

function signed [4:0] v_cast_s5; input signed [4:0] value; begin begin v_cast_s5=value; end  end endfunction
function signed [5:0] v_cast_s6; input signed [5:0] value; begin begin v_cast_s6=value; end  end endfunction
endmodule
