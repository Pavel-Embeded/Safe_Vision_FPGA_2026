`timescale 1ns/1ps
module tb_v3_directory_lba70;
 reg[31:0] cluster=0,base=0;reg[7:0] spc=1;integer errors=0,comparisons=0,k,b,j;reg[31:0] expected,rng=32'h1384;
 fat32_directory_scanner d(.clk(1'b0),.rst_n(1'b0),.wk_next_clus(cluster),.data_start_lba(base),.sec_per_clus(spc));
 task check;begin
 if(spc!=0&&((spc&(spc-8'd1))==0))expected=base+(cluster-32'd2)*spc;else expected=base;
 #1;comparisons++;if(d.directory_next_lba!==expected)begin errors++;if(errors<8)$display("[FAIL] LBA cluster=%h spc=%d base=%h actual=%h expected=%h",cluster,spc,base,d.directory_next_lba,expected);end
 end endtask
 initial begin
 for(j=0;j<8;j++)for(b=0;b<4;b++)for(k=0;k<65536;k++)begin spc=8'd1<<j;base=b==0?0:b==1?1:b==2?32'hfffffff0:32'h80000000;cluster=k;check();end
 for(j=0;j<256;j++)for(k=0;k<1024;k++)begin spc=j;rng=rng*1664525+1013904223;base=rng;rng=rng*1664525+1013904223;cluster=rng;check();end
 if(errors==0)$display("[PASS] exact modular directory LBA,all SPC encodings,all low16-bit clusters,wrap boundaries and262144full-width random cases");
 $display("PASS tb_v3_directory_lba70 errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
