`timescale 1ns/1ps
`include "safevision_defs.vh"


module tb_v3_directory_limit550;
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 wire scan_done,bad,en,dr,ev,ws,wr;wire[7:0] ec,ed;wire[31:0] addr,cur;wire[15:0] idx;
 reg ready=1,dv=0,last=0,done=0,reading=0;reg[7:0] data=0;integer byte_index=0,sectors=0,cycles=0,comparisons=0,errors=0;
 reg wd=0;reg[31:0] next_cluster=0;
 fat32_directory_scanner #(.FULL_NAMES(1)) d(.clk(clk),.rst_n(rst_n),.scan_en(start),.scan_done(scan_done),.dir_bad(bad),.err_code(ec),.err_detail(ed),
 .sec_per_clus(8'd128),.root_clus(32'd2),.root_dir_lba(32'd3),.data_start_lba(32'd3),
 .ent_valid(ev),.ent_ready(1'b1),.ent_index(idx),.sd_rd_addr(addr),.sd_rd_en(en),.sd_rd_ready(ready),
 .sd_data(data),.sd_data_valid(dv),.sd_data_ready(dr),.sd_data_last(last),.sd_rd_done(done),
 .sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0),
 .wk_cur_clus(cur),.wk_start(ws),.wk_rst_walk(wr),.wk_busy(1'b0),.wk_done(wd),.wk_next_clus(next_cluster),.wk_eoc(1'b0),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0),.name_address(8'd0));
 always @(posedge clk)if(rst_n)begin
  cycles<=cycles+1;done<=0;wd<=ws;if(ws)next_cluster<=cur+1;
  if(ev)begin errors=errors+1;$display("[FAIL] folder leaked as media key%0d",idx);end
  if(en&&ready)begin
   comparisons=comparisons+1;
   if(addr!=3+sectors)begin errors=errors+1;$display("[FAIL] directory LBA%0d expected%0d",addr,3+sectors);end
   sectors<=sectors+1;ready<=0;reading<=1;byte_index<=0;
  end
  if(dv&&dr)begin
   dv<=0;
   if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else byte_index<=byte_index+1;
  end else if(reading&&!dv)begin
   data<=byte_index%32==0?8'h41:byte_index%32==11?8'h10:8'h20;
   dv<=1;last<=byte_index==511;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
  wait(scan_done);@(negedge clk);comparisons=comparisons+1;
  if(!bad||ec!=`ERR_MEDIA_INVALID||ed!=`DET_DIR_OOB||sectors!=4096)begin
   errors=errors+1;$display("[FAIL] overflow must finish03/33 after4096sectors got bad%b %h/%h sectors%0d",bad,ec,ed,sectors);
  end
  if(!errors)$display("[PASS] 65536 actual directory slots terminate before zero-reserved key wraps; every LBA independently checked");
  $display("[TB] tb_v3_directory_limit550 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin repeat(6000000)@(negedge clk);$display("[FAIL] bounded directory limit watchdog errors=1");$finish;end
endmodule
