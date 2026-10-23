`timescale 1ns/1ps
`include "safevision_defs.vh"
module tb_v3_lba_timeout759;
 reg clk=0,rst=0,fstart=0,dstart=0;always #5 clk=~clk;
 reg[31:0]ftimer=0,dtimer=0;reg fvalid=0;wire freq,fread,ferr,fdone;wire[31:0]faddr;wire[7:0]fcode,fdetail;
 reg dv=0,last=0,ddone=0,wdone=0;reg[7:0]data=0;wire den,dr,dreq,dbad,dend;wire[7:0]dcode,ddetail;
 integer comparisons=0,errors=0,guard,i,drequests=0;
 v3_file_streamer_compact_ctx #(.EXTERNAL_LBA(1),.EXTERNAL_TIMER(1),.DIRECT_REQUEST_ADDRESS(1),.PIPELINED_LBA(1)) fs(
 .clk(clk),.rst_n(rst),.context_load(1'b0),.context_in(136'd0),.context_enable(1'b1),.stream_enable(1'b1),.start(fstart),.first_clus(32'd2),.file_size(32'd512),.ready(1'b1),
 .sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),.total_clus(32'd1000),.wk_busy(1'b0),.wk_done(1'b0),.wk_next_clus(32'd3),.wk_eoc(1'b0),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0),
 .sd_rd_ready(1'b1),.sd_data(8'd0),.sd_data_valid(1'b0),.sd_data_last(1'b0),.sd_rd_done(1'b0),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0),
 .sd_rd_en(fread),.sd_rd_addr(faddr),.error(ferr),.done(fdone),.err_code(fcode),.err_detail(fdetail),.external_lba(32'h55667788),.external_timeout_count(ftimer),.external_lba_valid(fvalid),.lba_request(freq));
 fat32_directory_scanner #(.EXTERNAL_LBA(1),.EXTERNAL_TIMER(1),.PIPELINED_LBA(1)) ds(
 .clk(clk),.rst_n(rst),.scan_en(dstart),.ent_ready(1'b1),.sec_per_clus(8'd1),.root_dir_lba(32'd16),.root_clus(32'd2),.data_start_lba(32'd16),
 .wk_busy(1'b0),.wk_done(wdone),.wk_next_clus(32'd3),.wk_eoc(1'b0),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0),
 .sd_rd_ready(1'b1),.sd_data(data),.sd_data_valid(dv),.sd_data_ready(dr),.sd_data_last(last),.sd_rd_done(ddone),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0),
 .sd_rd_en(den),.scan_done(dend),.dir_bad(dbad),.err_code(dcode),.err_detail(ddetail),.name_address(8'd0),.external_lba(32'h11223344),.external_timeout_count(dtimer),.external_lba_valid(1'b0),.lba_request(dreq));
 task check(input bit ok,input string msg);begin comparisons++;if(!ok)begin errors++;$display("[FAIL] %s",msg);end end endtask
 always @(posedge clk)if(rst&&den)drequests++;
 initial begin
  repeat(3)@(negedge clk);rst=1;fstart=1;@(negedge clk);fstart=0;guard=0;
  while(!freq&&guard<16)begin @(negedge clk);guard++;end
  check(freq,"file enters explicit pending-LBA state");ftimer=`SD_TO_DATA;
  guard=0;while(!fdone&&guard<16)begin @(negedge clk);guard++;check(!fread,"no file SD request before valid LBA");end
  check(fdone&&ferr&&fcode==`ERR_SD_IO&&fdetail==`DET_SD_TOKEN_TO,"file LBA wait is bounded and reports token timeout");
  rst=0;ftimer=0;repeat(3)@(negedge clk);rst=1;dstart=1;@(negedge clk);dstart=0;
  guard=0;while(!dr&&guard<16)begin @(negedge clk);guard++;end
  check(dr,"directory starts initial root sector");
  for(i=0;i<512;i++)begin
   @(negedge clk);data=i%32==0?8'he5:8'd0;dv=1;last=i==511;
   guard=0;while(!dr&&guard<32)begin @(negedge clk);guard++;end
   check(dr,"each deleted-entry byte accepted with backpressure");@(posedge clk);#1;
  end
  @(negedge clk);dv=0;last=0;ddone=1;@(negedge clk);ddone=0;wdone=1;
  guard=0;while(!dreq&&guard<32)begin @(negedge clk);guard++;end
  check(dreq,"directory follows real complete-sector walk into LBA wait");wdone=0;dtimer=`SD_TO_DATA;
  guard=0;while(!dend&&guard<16)begin @(negedge clk);guard++;end
  check(dend&&dbad&&dcode==`ERR_SD_IO&&ddetail==`DET_SD_TOKEN_TO,"directory LBA wait is bounded and reports token timeout");
  check(drequests==1,"pending directory LBA cannot launch an unqualified second read");
  rst=0;dtimer=0;ftimer=0;repeat(3)@(negedge clk);rst=1;fstart=1;fvalid=1;@(negedge clk);fstart=0;
  guard=0;while(!fread&&guard<16)begin @(negedge clk);guard++;end
  check(fread&&faddr==32'h55667788&&!ferr,"reset clears failure and valid LBA resumes correct public request");
  if(errors==0)$display("[PASS] bounded file/directory LBA waits,complete root sector,timeout metadata,no invalid requests,reset recovery");
  $display("[TB] tb_v3_lba_timeout759 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] timeout contract watchdog errors=1");$finish;end
endmodule
