`timescale 1ns/1ps
module tb_v3_ingress_credit;
 reg[9:0] level10=0,level9=0;reg[1:0] part=0;
 wire[8:0] pairs10,pairs9;wire[10:0] words10,words9;wire room10,room9;
 integer i,j,errors=0,checks=0;
 v3_pcm_ingress_shared_fifo default_dut(.rst(1'b1),.wr_clk(1'b0),.rd_clk(1'b0),.wr_data(128'd0),.wr_valid(4'd0),.wr_pairs(pairs10),.wr_words(words10),.sector_room(room10),.rd_ready(4'd0));
 v3_pcm_ingress_shared_fifo #(.AW(9)) compact_dut(.rst(1'b1),.wr_clk(1'b0),.rd_clk(1'b0),.wr_data(128'd0),.wr_valid(4'd0),.wr_pairs(pairs9),.wr_words(words9),.sector_room(room9),.rd_ready(4'd0));
 initial begin
  force default_dut.words=level10;force default_dut.write_part=part;force default_dut.wr_rst_n=1;
  force compact_dut.words=level9;force compact_dut.write_part=part;force compact_dut.wr_rst_n=1;
  for(i=0;i<1024;i = i + 1)for(j=0;j<4;j = j + 1)begin
   level10=i;part=j;#1;checks = checks + 1;
   if(pairs10!==v_cast_u9((i+2)/3+(j!=0))||words10!==v_cast_s11(i)||room10!==((j==0)&&(i<=632)))begin errors = errors + 1;if(errors<5)$display("[FAIL] default level=%0d part=%0d",i,j);end
  end
  for(i=0;i<512;i = i + 1)for(j=0;j<4;j = j + 1)begin
   level9=i;part=j;#1;checks = checks + 1;
   if(pairs9!==v_cast_u9((i+2)/3+(j!=0))||words9!==v_cast_s11(i)||room9!==((j==0)&&(i<=120)))begin errors = errors + 1;if(errors<5)$display("[FAIL] compact level=%0d part=%0d",i,j);end
   if(room9&&511-i<384+7)begin errors = errors + 1;$display("[FAIL] insufficient reservation");end
  end
  if(!errors)$display("[PASS] exact integer public credit all1024/default and512/compact levels x4 partial states, sector guard384+7");
  $display("[TB] tb_v3_ingress_credit done comparisons=%0d errors=%0d",checks,errors);$finish;
 end

function [8:0] v_cast_u9; input [8:0] value; begin begin v_cast_u9=value; end  end endfunction
function signed [10:0] v_cast_s11; input signed [10:0] value; begin begin v_cast_s11=value; end  end endfunction
endmodule

