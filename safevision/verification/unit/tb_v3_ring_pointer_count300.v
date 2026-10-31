`timescale 1ns/1ps


module tb_v3_ring_pointer_count300;
 reg clk=0,rst=0,ack=0,busy=0,rv=0;
 wire[63:0]levels;wire[3:0]pre;
 integer errors=0,comparisons=0,v,c,d,k,owner,step;
 integer w[0:3],r[0:3],expected[0:3];reg[31:0]random_state=32'h875ac124;
 v3_pcm_ring dut(.clk(clk),.rst_n(rst),.in_data(128'd0),.in_valid(4'd0),.commit_valid(1'b0),.commit_slot(2'd0),.commit_generation(8'd0),.fallback(4'd0),.out_ready(1'b0),.output_level(10'd0),.ack(ack),.busy(busy),.rdata(32'd0),.rvalid(rv),.levels(levels),.prefetched(pre));
 task verify;
  begin  for(k=0;k<4;k = k + 1)begin
   comparisons = comparisons + 1;
   if(levels[k*16+:16]!==v_cast_s16(expected[k])||pre[k]!==v_cast_u1(expected[k]>=800))begin
    errors = errors + 1;if(errors<8)$display("[FAIL] pointer induction owner%0d slot%0d expected%0d level%0d",owner,k,expected[k],levels[k*16+:16]);
   end
  end
  end endtask
 initial begin
  #1;rst=1;


  for(d=0;d<2;d = d + 1)for(v=0;v<32768;v = v + 1)for(c=0;c<8;c = c + 1)begin
   owner=(v+c)%4;step=d ? -1:1;
   random_state=random_state*32'd1664525+32'd1013904223;
   for(k=0;k<4;k = k + 1)begin
    w[k]=(v+k*83)%32768;
    case(c)
     0:expected[k]=0;1:expected[k]=1;2:expected[k]=511;
     3:expected[k]=512;4:expected[k]=16383;5:expected[k]=16384;
     6:expected[k]=32767;default:expected[k]=(random_state>>1)%32768;
    endcase
    r[k]=(w[k]-expected[k]+32768)%32768;
   end
   dut.wp[0]=v_cast_s15(w[0]);dut.wp[1]=v_cast_s15(w[1]);dut.wp[2]=v_cast_s15(w[2]);dut.wp[3]=v_cast_s15(w[3]);
   dut.rp[0]=v_cast_s15(r[0]);dut.rp[1]=v_cast_s15(r[1]);dut.rp[2]=v_cast_s15(r[2]);dut.rp[3]=v_cast_s15(r[3]);
   dut.state=d ? 1:2;dut.reading=d;dut.seen_data=0;dut.owner=v_cast_s2(owner);ack=1;rv=d;busy=0;
   #1;verify();clk=1;#1;
   expected[owner]=(expected[owner]+step+32768)%32768;
   verify();clk=0;
  end
  if(!errors)$display("[PASS] actual pointer occupancy: every15-bit pointer, full/empty distinction, both event directions, all4banks, modular induction");
  $display("[TB] tb_v3_ring_pointer_count300 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end

function [0:0] v_cast_u1; input [0:0] value; begin  v_cast_u1=value;   end endfunction
function signed [1:0] v_cast_s2; input signed [1:0] value; begin  v_cast_s2=value;   end endfunction
function signed [14:0] v_cast_s15; input signed [14:0] value; begin  v_cast_s15=value;   end endfunction
function signed [15:0] v_cast_s16; input signed [15:0] value; begin  v_cast_s16=value;   end endfunction
endmodule
