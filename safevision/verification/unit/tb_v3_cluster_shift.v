`timescale 1ns/1ps
module tb_v3_cluster_shift;
 reg clk=0;always #5 clk=~clk;
 fat32_directory_scanner #(.SV_MEDIA_ONLY(1)) scanner(.clk(clk),.rst_n(1'b0));
 v3_file_streamer_compact_ctx streamer(.clk(clk),.rst_n(1'b0));
 integer errors=0,comparisons=0,s,b,i;reg[31:0] d,expected,a,c,random_state=32'h4b92dc17;
 task compare(input[31:0] value,input[7:0] spc);begin begin
  expected=(spc!=0 && (spc&(spc-1))==0) ? value*spc:32'd0;
  a=scanner.cluster_sectors(value,spc);c=streamer.cluster_sectors(value,spc);
  if(a!==expected || c!==expected)begin errors=errors+1;if(errors<8)$display("[FAIL] SPC=%0d delta=%h scanner=%h streamer=%h expected=%h",spc,value,a,c,expected);end
  comparisons=comparisons+2;
 end  end endtask
 initial begin
  #1;
  for(s=0;s<256;s=s+1)begin
   compare(0,s);compare(32'hffffffff,s);compare(32'h80000001,s);
   for(b=0;b<32;b=b+1)begin compare(32'b1<<b,s);compare(~(32'b1<<b),s);end
  end
  for(i=0;i<100000;i=i+1)begin
   random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);d=random_state;
   compare(d,i[7:0]);
  end
  if(errors==0)$display("[PASS] full32 modular arithmetic, all256 legal/invalid SPC values, every bit and 100000 random deltas");
  $display("[TB] tb_v3_cluster_shift done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
