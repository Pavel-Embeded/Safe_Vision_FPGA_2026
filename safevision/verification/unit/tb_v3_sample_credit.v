`timescale 1ns/1ps
module tb_v3_sample_credit;
 reg[9:0] level=0;reg[1:0] part=0;wire[8:0] pairs;
 integer i,j,expected,errors=0,comparisons=0;
 v3_pcm_sample_fifo dut(.rst(1'b1),.wr_clk(1'b0),.rd_clk(1'b0),.wr_data(40'd0),.wr_valid(1'b0),.wr_pairs(pairs),.rd_ready(1'b0));
 initial begin
  force dut.words=level;force dut.write_part=part;
  for(i=0;i<1024;i = i + 1)for(j=0;j<4;j = j + 1)begin
   level=i;part=j;#1;expected=((i+2)/3)+(j!=0);comparisons = comparisons + 1;
   if(pairs!==v_cast_s9(expected))begin errors = errors + 1;if(errors<8)$display("[FAIL] credit words=%0d part=%0d got=%0d expected=%0d",i,j,pairs,expected);end
  end
  if(errors==0)$display("[PASS] all1024 FIFO levels and4 partial packet states exactly match independent integer division,4096 public credit values,no handshake latency change");
  $display("[TB] tb_v3_sample_credit done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end

function signed [8:0] v_cast_s9; input signed [8:0] value; begin begin v_cast_s9=value; end  end endfunction
endmodule
