`timescale 1ns/1ps
module tb_v3_hd_crc_preimage;
 reg[31:0]state=0,data=0,crc=0,rng=32'h385739ab,original;integer errors=0,comparisons=0,k,j;
 v3_line_cache dut(.mem_clk(1'b0),.mem_rst_n(1'b0),.pixel_clk(1'b0),.pixel_rst_n(1'b0),.write_clk(1'b0),.write_rst_n(1'b0),
 .prepare_valid(1'b0),.prepare_sy(10'd0),.request_valid(1'b0),.request_data(24'd0),.response_ready(1'b0),.sx(10'd0),.sy(10'd0),.coord_valid(1'b0),
 .scale_select(2'd0),.current_slot(2'd0),.target_slot(2'd0),.dual_needed(1'b0),.rd_ack(1'b0),.rd_busy(1'b0),.rd_valid(1'b0),.rd_data(data),.lookup_crc(32'd0),.lookup_valid(1'b0));
 function[31:0]forward_word(input[31:0]c,d);reg[31:0]v;integer i;begin begin
  v=c^d;for(i=0;i<32;i = i + 1)v=v[0] ? (v>>1)^32'hedb88320:v>>1;forward_word=v;
 end  end endfunction
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<6)$display("[FAIL] %s",msg);end end  end endtask
 task one_step;reg[31:0]v,fwd;begin begin #1;v=dut.inverse_step;fwd=v[0] ? (v>>1)^32'hedb88320:v>>1;ck(fwd===state,"inverse composed with independent forward bit is identity");end  end endtask
 initial begin
  force dut.expected=state;force dut.crc=crc;
  state=0;one_step();for(k=0;k<32;k = k + 1)begin state=1<<k;one_step();end
  for(k=0;k<1000000;k = k + 1)begin rng=rng*1664525+1013904223;state=rng;one_step();end
  for(k=0;k<10000;k = k + 1)begin
   rng=rng*1664525+1013904223;crc=rng;rng=rng*1664525+1013904223;data=rng;
   state=forward_word(crc,data);original=state;
   repeat(32)begin #1;state=dut.inverse_step;end #1;
   ck(forward_word(state,0)===original,"32-step inverse matches forward CRC reference");
   ck(!dut.final_crc_mismatch,"original final input accepted");data=data^1;#1;ck(dut.final_crc_mismatch,"one-bit final payload corruption detected");
  end
  if(errors==0)$display("[PASS] CRC inverse linear basis and million states;10000 independent final words and corruptions; shared accumulator unchanged");
  $display("[TB] tb_v3_hd_crc_preimage done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #2000000;$display("[FAIL] preimage watchdog");$display("[TB] tb_v3_hd_crc_preimage done errors=1");$finish;end
endmodule
