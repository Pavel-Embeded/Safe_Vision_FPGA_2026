`timescale 1ns/1ps

module tb_v3_lba_pipeline747;
 reg clk=0,rst=0,start=0;always #5 clk=~clk;
 reg[31:0]first=0,base=0;reg[7:0]spc=1;wire[444:0]cmd;wire[836:0]rsp0,rsp1;
 assign cmd={1'b1,1'b0,1'b1,1'b0,1'b1,start,first,32'd512,1'b1,265'd0,1'b0,32'd0,1'b0,1'b0,32'd0,3'b010,3'd0,3'd0,3'd0,3'd0,3'd0,8'd0,8'd0,8'd0};
 v3_shared_fs_service #(.FLEX_FILES(0)) old_path(.clk(clk),.rst_n(rst),.sec_per_clus(spc),.fat_start_lba(32'd1),.data_start_lba(base),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'hfffffff),.core_cmd(cmd),.core_rsp(rsp0),.name_address(8'd0),.name_data(),.name_length());
 v3_shared_fs_service #(.FLEX_FILES(1)) new_path(.clk(clk),.rst_n(rst),.sec_per_clus(spc),.fat_start_lba(32'd1),.data_start_lba(base),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'hfffffff),.core_cmd(cmd),.core_rsp(rsp1),.name_address(8'd0),.name_data(),.name_length());
 integer errors=0,comparisons=0,k,guard;reg seen0,seen1;reg[31:0]random_value=32'hc58a03b1,expected;reg[63:0]wide;
 task check(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<16)$display("[FAIL] %s k=%0d first=%h base=%h spc=%0d",msg,k,first,base,spc);end   end endtask
 initial begin
  check(new_path.fs.PIPELINED_LBA==1&&new_path.ds.PIPELINED_LBA==1,"production file and directory pipeline enabled");
  for(k=0;k<4096;k = k + 1)begin
   @(negedge clk);rst=0;start=0;repeat(2)@(negedge clk);
   random_value=random_value*1664525+1013904223;first=random_value;
   random_value=random_value*22695477+1;base=random_value;
   case(k%16)
    0:spc=1;1:spc=2;2:spc=4;3:spc=8;4:spc=16;5:spc=32;6:spc=64;7:spc=128;
    8:spc=0;9:spc=3;10:spc=5;11:spc=255;12:spc=127;13:spc=129;14:spc=7;default:spc=16;
   endcase
   if(k<16)begin first=k%4==0 ? 0:k%4==1 ? 1:k%4==2 ? 32'hffffffff:32'hfffffffe;base=32'hfffffff0;end
   wide=({32'd0,first}-64'd2)*{56'd0,spc}+{32'd0,base};
   expected=(spc!=0&&((spc&(spc-1))==0)) ? wide[31:0]:base;
   rst=1;start=1;@(negedge clk);start=0;seen0=0;seen1=0;guard=0;
   while(!(seen0&&seen1)&&guard<32)begin
    @(posedge clk);#1;
    if(old_path.f_sd_rd_en)begin check(!seen0,"one legacy initial request");check(old_path.f_sd_rd_addr===expected,"legacy modulo32 LBA matches independent64-bit oracle");seen0=1;end
    if(new_path.f_sd_rd_en)begin check(guard>=3,"request waits for registered multiply/add result");check(!seen1,"one pipelined initial request");check(new_path.f_sd_rd_addr===expected,"pipelined modulo32 LBA matches independent64-bit oracle");seen1=1;end
    guard = guard + 1;
   end
   check(seen0&&seen1,"bounded pipeline response under all SPC encodings and address carry boundaries");
   check(!new_path.d_sd_rd_en,"file request never leaks to directory channel");
  end
  if(errors==0)$display("[PASS]4096 reset/start contracts, legacy and pipeline,legal/illegal SPC,full32-bit cluster/base overflow,independent64-bit oracle");
  $display("[TB] tb_v3_lba_pipeline747 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] LBA pipeline watchdog errors=1");$finish;end
endmodule
