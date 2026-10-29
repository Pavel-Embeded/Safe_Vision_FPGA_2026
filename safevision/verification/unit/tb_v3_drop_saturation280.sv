`timescale 1ns/1ps
module tb_v3_drop_saturation280;
 reg clk=0,rst=0;reg[1:0] loss=0;reg[31:0] seed=0,rng=32'h919abcde,expected;integer errors=0,comparisons=0,i,k;
 v3_uart_link dut(.clk(clk),.rst_n(rst),.rxd(1'b1),.reply_valid(1'b0),.reply_code(8'd0),.reply_value(32'd0),.evt_valid(1'b0),.evt_code(8'd0),.evt_src(4'd0),.evt_ts(32'd0));
 task check;begin dut.reply_dropped=seed;
  expected=seed>32'hffffffff-loss?32'hffffffff:seed+loss;#1;comparisons++;
  if(dut.dropped_next!==expected)begin errors++;if(errors<6)$display("[FAIL] saturation seed%h loss%0d got%h want%h",seed,loss,dut.dropped_next,expected);end
 end endtask
 initial begin force dut.lost=loss;#1;rst=1;
  for(k=0;k<3;k++)begin loss=k;
   for(i=0;i<65536;i++)begin seed=i;check();seed=32'hffff0000|i;check();end
   for(i=0;i<1000000;i++)begin rng=rng*1664525+1013904223;seed=rng;check();end
  end
  if(!errors)$display("[PASS] actual UART saturated-drop arithmetic:all low/high16-bit values,0/1/2 loss,3million random values");
  $display("[TB] tb_v3_drop_saturation280 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
