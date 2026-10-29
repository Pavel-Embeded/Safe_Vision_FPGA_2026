module tb_v3_paired_rows_base288;
 wire d0,d1;wire signed [31:0] e0,e1,c0,c1;
 paired_rows_case275 #(.PHASE(0)) a(d0,e0,c0);paired_rows_case275 #(.PHASE(5)) b(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[TB] tb_v3_paired_rows_base288 done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
 initial begin #100000000;$display("[FAIL] paired-row watchdog");$display("[TB] tb_v3_paired_rows_base288 done errors=1 comparisons=0");$finish;end
endmodule
module tb_v3_paired_rows_hd288;
 wire d0,d1;wire signed [31:0] e0,e1,c0,c1;
 paired_rows_case275 #(.PHASE(0)) a(d0,e0,c0);paired_rows_case275 #(.PHASE(5)) b(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[TB] tb_v3_paired_rows_hd288 done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
 initial begin #100000000;$display("[FAIL] paired-row watchdog");$display("[TB] tb_v3_paired_rows_hd288 done errors=1 comparisons=0");$finish;end
endmodule
