`timescale 1ns/1ps
module slot_partition_case249(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 reg clk=0;always #5 clk=~clk;reg[31:0]a=0,b=0;integer prefix,low,k;reg[31:0]r=32'hade1f234;
 v3_row_integrity dut(.clk(clk),.rst_n(1'b0),.frame_begin(1'b0),.frame_slot(2'd0),.top_down(1'b1),.accepted(1'b0),.write_addr(a),.write_data(32'd0),.verify_start(1'b0),.verify_allow(1'b0),.rd_ack(1'b0),.rd_busy(1'b0),.rd_valid(1'b0),.rd_data(32'd0),.lookup_addr(b));
 function[1:0] old_partition(input[31:0]v);begin  old_partition=v>=32'h001e0000  ?  3 : v>=32'h00140000  ?  2 : v>=32'h000a0000  ?  1 : 0;  end endfunction
 function[31:0]rnd(input[31:0]v);reg[31:0]z;begin  z=v^(v<<13);z=z^(z>>17);rnd=z^(z<<5);  end endfunction
 task check;begin  #1;comparisons = comparisons + (2);
  if(dut.source_slot!==old_partition(a)||dut.query_slot!==old_partition(b))begin errors = errors + 1;if(errors<8)$display("[FAIL] full32-bit slot partition a=%h b=%h",a,b);end
   end endtask
 initial begin


  for(prefix=0;prefix<32768;prefix = prefix + 1)for(low=0;low<3;low = low + 1)begin
   r=rnd(r);a={v_cast_s15(prefix),low==0 ? 17'd0:low==1 ? 17'h1ffff:r[16:0]};b=~a;check();
  end
  for(k=0;k<1000000;k = k + 1)begin r=rnd(r);a=r;b=rnd(r^32'h91abcde0);check();end
  if(!errors)$display("[PASS] actual producer and lookup partition:all32768 high intervals,both edges,interiors,1million random32-bit pairs");
  done=1;
 end

function signed [14:0] v_cast_s15; input signed [14:0] value; begin  v_cast_s15=value;   end endfunction
endmodule
module tb_v3_slot_partition_base249;
 wire done;wire signed [31:0] errors,comparisons;slot_partition_case249 x(done,errors,comparisons);
 initial begin wait(done);$display("[TB] tb_v3_slot_partition_base249 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
endmodule
module tb_v3_slot_partition_hd249;
 wire done;wire signed [31:0] errors,comparisons;slot_partition_case249 x(done,errors,comparisons);
 initial begin wait(done);$display("[TB] tb_v3_slot_partition_hd249 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
endmodule
