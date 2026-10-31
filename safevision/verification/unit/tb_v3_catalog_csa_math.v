`timescale 1ns/1ps
module tb_v3_catalog_csa_math;
 reg[23:0]number=0;reg[7:0]rx_data=0;reg[23:0]expected;reg[31:0]lfsr=32'h5ae61239;
 integer n,d,k,errors=0,comparisons=0;
 v3_command_parser_catalog #(.CATALOG_FILE("v3_command_catalog.mem")) dut(.clk(1'b0),.rst_n(1'b0),.rx_valid(1'b0),.rx_data(rx_data));
 task compare;begin  #1;expected=number*24'd10+{20'd0,rx_data[3:0]};comparisons = comparisons + 1;
  if(dut.decimal_next!==expected)begin errors = errors + 1;if(errors<6)$display("[FAIL] decimal n=%h digit=%h got=%h expected=%h",number,rx_data[3:0],dut.decimal_next,expected);end
   end endtask
 initial begin
  force dut.number=number;
  for(n=0;n<1000000;n = n + 1)for(d=0;d<16;d = d + 1)begin number=n;rx_data=d;compare();end
  for(k=0;k<100000;k = k + 1)begin lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};number=lfsr[23:0];rx_data=lfsr[31:24];compare();end
  number=24'hffffff;for(d=0;d<16;d = d + 1)begin rx_data=d;compare();end
  if(errors==0)$display("[PASS] all legal pre-digit accumulators times16nibbles plus100k full24-bit states; exact modulo arithmetic");
  $display("[TB] tb_v3_catalog_csa_math done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #20000000;errors = errors + 1;$display("[FAIL] bounded decimal exhaustive timeout");$display("[TB] tb_v3_catalog_csa_math done comparisons=%0d errors=%0d",comparisons,errors);$finish;end
endmodule
