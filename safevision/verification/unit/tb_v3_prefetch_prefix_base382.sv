`timescale 1ns/1ps
module tb_v3_prefetch_prefix_base382;
 reg[31:0] address=0,expected;reg[6:0] step=0;reg high_zero=0,high_ones=0;
 integer errors=0,comparisons=0,h,n,k,low;reg[31:0] rng=32'h512723fe;
 sdram_app_adapter d(.clk(1'b0),.rst_n(1'b0));
 task check;begin
  high_zero=address[31:21]==0;high_ones=address[31:21]==11'h7ff;
  expected=address+step;#1;comparisons++;
  if(d.prefetch_sum[20:0]!==expected[20:0]||d.next_prefetch_in_range!==(expected<32'h200000))begin
   errors++;if(errors<7)$display("[FAIL] prefix addr=%h step=%d low=%h range=%b expected=%h",address,step,d.prefetch_sum[20:0],d.next_prefetch_in_range,expected);
  end
 end endtask
 initial begin
  force d.rfbase=address[20:0];force d.rfbase_high_zero=high_zero;force d.rfbase_high_ones=high_ones;force d.read_words=step;


  for(h=0;h<2048;h++)for(n=0;n<=16;n++)for(k=0;k<5;k++)begin
   case(k)0:low=0;1:low=2097151;2:low=(2097152-n-1)&2097151;3:low=(2097152-n)&2097151;default:low=(2097152-n+1)&2097151;endcase
   address=(h<<21)|low;step=n;check();
  end
  for(n=0;n<100000;n++)begin rng=rng*1664525+1013904223;address=rng;step=(rng>>24)%(16+1);check();end
  if(errors==0)$display("[PASS] all32-bit prefix classes, every increment, carry threshold witnesses and100k random addresses; exact modular wrap and capacity test");
  $display("[TB] tb_v3_prefetch_prefix_base382 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] watchdog");$display("[TB] tb_v3_prefetch_prefix_base382 done errors=1 comparisons=0");$finish;end
endmodule
