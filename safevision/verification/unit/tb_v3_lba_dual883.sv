`timescale 1ns/1ps
// Independent modulo-32 mathematical oracle at every REF edge. This complements
// the unchanged public file/directory start and timeout contract regressions.
module tb_v3_lba_dual883;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[31:0] directory_cluster=0,file_cluster=0,base=0;
 reg[7:0] spc=0;reg owner=0,request=0;
 wire[836:0] response;
 v3_shared_fs_service #(.FLEX_FILES(1)) dut(.clk(clk),.rst_n(rst),
  .sec_per_clus(spc),.fat_start_lba(32'd1),.data_start_lba(base),
  .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'hfffffff),
  .core_cmd(445'd0),.core_rsp(response),.name_address(8'd0),.name_data(),.name_length());
 reg valid_first=0,valid_second=0,owner_first=0,owner_second=0;
 reg[31:0] expected_first=0,expected_second=0;
 integer errors=0,comparisons=0,k,n,bins[0:255][0:1],reset_count=0;
 reg[31:0] random_state=32'h8c75a2d1;
 function[31:0] mathematical_lba(input[31:0] dc,fc,origin,input[7:0] factor,input bit selected);
  reg[63:0] wide;reg[31:0] cluster;begin
   cluster=selected?dc:fc;
   wide=({32'd0,cluster}-64'd2)*{56'd0,factor}+{32'd0,origin};
   mathematical_lba=(factor!=0&&((factor&(factor-8'd1))==0))?wide[31:0]:origin;
  end
 endfunction
 task check(input bit ok,input string message);begin
  comparisons++;if(!ok)begin errors++;if(errors<12)$display("[FAIL] %s k=%0d spc=%0d owner=%b",message,k,spc,owner);end
 end endtask
 always @(posedge clk or negedge rst)begin
  if(!rst)begin valid_first<=0;valid_second<=0;owner_first<=0;owner_second<=0;end
  else begin
   expected_first<=mathematical_lba(directory_cluster,file_cluster,base,spc,owner);
   expected_second<=expected_first;
   valid_first<=request;valid_second<=valid_first;
   owner_first<=owner;owner_second<=owner_first;
  end
 end
 always @(posedge clk)begin #1;
  if(rst)begin
   check(dut.directory_lba_valid===(valid_second&&owner_second),"directory valid has exact two-edge latency and owner");
   check(dut.file_lba_valid===(valid_second&&!owner_second),"file valid has exact two-edge latency and owner");
   check(dut.registered_lba.owner2===owner_second,"owner tag remains aligned even in idle input changes");
   if(valid_second)check(dut.shared_lba===expected_second,"independent64-bit modulo32 LBA for preceding sample");
   if(request)bins[spc][owner]++;
  end else check(!dut.directory_lba_valid&&!dut.file_lba_valid,"asynchronous epoch discards both pending valid tags");
 end
 initial begin
  for(k=0;k<256;k++)begin bins[k][0]=0;bins[k][1]=0;end
  force dut.directory_lba_cluster=directory_cluster;
  force dut.file_lba_cluster=file_cluster;
  force dut.directory_lba_active=owner;
  force dut.directory_lba_request=request&&owner;
  force dut.file_lba_request=request&&!owner;
  repeat(3)@(negedge clk);
  for(k=0;k<32768;k++)begin
   rst=(k%257!=256);if(!rst)reset_count++;
   owner=k[0];spc=k[8:1];request=(k%7!=0);
   random_state=random_state*32'd1664525+32'd1013904223;directory_cluster=random_state;
   random_state=random_state*32'd22695477+32'd1;file_cluster=random_state;
   random_state=random_state*32'd1103515245+32'd12345;base=random_state;
   if(k<2048)begin
    case((k/512)%4)
     0:begin directory_cluster=0;file_cluster=1;base=32'hfffffff0;end
     1:begin directory_cluster=32'hffffffff;file_cluster=32'hfffffffe;base=0;end
     2:begin directory_cluster=32'h0000ffff;file_cluster=32'hffff0000;base=32'hffffffff;end
     3:begin directory_cluster=32'h7fffffff;file_cluster=32'h80000000;base=32'h80000000;end
    endcase
   end
   @(negedge clk);
  end
  rst=1;request=0;repeat(4)@(negedge clk);
  for(k=0;k<256;k++)for(n=0;n<2;n++)check(bins[k][n]>0,"every legal/illegal SPC exercised on each owner");
  check(reset_count>100,"resets interrupt continuously interleaved outstanding pipeline requests");
  if(!errors)$display("[PASS] all256 SPCs,both owners,continuous/idle requests,full32-bit wraps and mid-pipeline reset");
  $display("[TB] tb_v3_lba_dual883 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #2000000;$display("[FAIL] two-edge LBA watchdog errors=1");$finish;end
endmodule
