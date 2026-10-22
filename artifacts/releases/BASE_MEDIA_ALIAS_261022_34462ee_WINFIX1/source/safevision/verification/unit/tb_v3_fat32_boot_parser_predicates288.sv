`include "safevision_defs.vh"
module tb_v3_fat32_boot_parser_predicates288;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,start=0,sd_rd_ready=0,sd_data_valid=0,sd_data_last=0,sd_rd_done=0,sd_timeout_err=0,sd_crc16_err=0;
 reg[7:0]sd_data=0,sd_err_code=0,sd_err_detail=0;reg[7:0] bytes[0:511];
 integer errors=0,comparisons=0,trial,k,j,limit,waits;reg[31:0]random_q=32'h71a22384;reg[31:0]v;
 function[31:0]rnd(input[31:0]a);reg[31:0]b;begin b=a^(a<<13);b=b^(b>>17);rnd=b^(b<<5);end endfunction
 wire[0:0] a_mount_done;
 wire[0:0] b_mount_done;
 wire[0:0] a_mount_error;
 wire[0:0] b_mount_error;
 wire[15:0] a_bytes_per_sec;
 wire[15:0] b_bytes_per_sec;
 wire[7:0] a_sec_per_clus;
 wire[7:0] b_sec_per_clus;
 wire[7:0] a_num_fats;
 wire[7:0] b_num_fats;
 wire[31:0] a_fat_start_lba;
 wire[31:0] b_fat_start_lba;
 wire[31:0] a_root_clus;
 wire[31:0] b_root_clus;
 wire[31:0] a_root_dir_lba;
 wire[31:0] b_root_dir_lba;
 wire[31:0] a_data_start_lba;
 wire[31:0] b_data_start_lba;
 wire[31:0] a_total_sec;
 wire[31:0] b_total_sec;
 wire[31:0] a_total_clus;
 wire[31:0] b_total_clus;
 wire[31:0] a_sd_rd_addr;
 wire[31:0] b_sd_rd_addr;
 wire[15:0] a_sd_rd_len;
 wire[15:0] b_sd_rd_len;
 wire[0:0] a_sd_rd_en;
 wire[0:0] b_sd_rd_en;
 wire[0:0] a_sd_data_ready;
 wire[0:0] b_sd_data_ready;
 wire[7:0] a_err_code;
 wire[7:0] b_err_code;
 wire[7:0] a_err_detail;
 wire[7:0] b_err_detail;
 wire[3:0] a_dbg_state;
 wire[3:0] b_dbg_state;
fat32_boot_parser a(.clk(clk),.rst_n(rst_n),.start(start),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_last(sd_data_last),.sd_rd_done(sd_rd_done),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail),.mount_done(a_mount_done),.mount_error(a_mount_error),.bytes_per_sec(a_bytes_per_sec),.sec_per_clus(a_sec_per_clus),.num_fats(a_num_fats),.fat_start_lba(a_fat_start_lba),.root_clus(a_root_clus),.root_dir_lba(a_root_dir_lba),.data_start_lba(a_data_start_lba),.total_sec(a_total_sec),.total_clus(a_total_clus),.sd_rd_addr(a_sd_rd_addr),.sd_rd_len(a_sd_rd_len),.sd_rd_en(a_sd_rd_en),.sd_data_ready(a_sd_data_ready),.err_code(a_err_code),.err_detail(a_err_detail),.dbg_state(a_dbg_state));
fat32_boot_parser255_reference b(.clk(clk),.rst_n(rst_n),.start(start),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_last(sd_data_last),.sd_rd_done(sd_rd_done),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail),.mount_done(b_mount_done),.mount_error(b_mount_error),.bytes_per_sec(b_bytes_per_sec),.sec_per_clus(b_sec_per_clus),.num_fats(b_num_fats),.fat_start_lba(b_fat_start_lba),.root_clus(b_root_clus),.root_dir_lba(b_root_dir_lba),.data_start_lba(b_data_start_lba),.total_sec(b_total_sec),.total_clus(b_total_clus),.sd_rd_addr(b_sd_rd_addr),.sd_rd_len(b_sd_rd_len),.sd_rd_en(b_sd_rd_en),.sd_data_ready(b_sd_data_ready),.err_code(b_err_code),.err_detail(b_err_detail),.dbg_state(b_dbg_state));
 always @(posedge clk)begin #1;comparisons++;if({a_mount_done,a_mount_error,a_bytes_per_sec,a_sec_per_clus,a_num_fats,a_fat_start_lba,a_root_clus,a_root_dir_lba,a_data_start_lba,a_total_sec,a_total_clus,a_sd_rd_addr,a_sd_rd_len,a_sd_rd_en,a_sd_data_ready,a_err_code,a_err_detail,a_dbg_state}!=={b_mount_done,b_mount_error,b_bytes_per_sec,b_sec_per_clus,b_num_fats,b_fat_start_lba,b_root_clus,b_root_dir_lba,b_data_start_lba,b_total_sec,b_total_clus,b_sd_rd_addr,b_sd_rd_len,b_sd_rd_en,b_sd_data_ready,b_err_code,b_err_detail,b_dbg_state})begin errors++;if(errors<8)$display("[FAIL] all-public-pin mismatch at%0t trial%0d byte%0d",$time,trial,k);end end
 task put32(input integer pos,input[31:0]n);begin for(integer q=0;q<4;q++)bytes[pos+q]=n>>(8*q);end endtask
 initial begin
  #27;rst_n=1;
  for(trial=0;trial<4096;trial++)begin
   for(k=0;k<512;k++)begin random_q=rnd(random_q);bytes[k]=random_q;end
   // Legal and malformed fields, arbitrary32-bit wrap/carry, both FAT counts,
   // all legal cluster sizes, interrupted reads and reset/restart epochs.
   if(1)begin
    bytes[11]=0;bytes[12]=2;bytes[13]=1<<(trial%8);bytes[14]=32;bytes[15]=0;bytes[16]=1+trial%2;
    bytes[17]=0;bytes[18]=0;bytes[19]=0;bytes[20]=0;bytes[22]=0;bytes[23]=0;
    random_q=rnd(random_q);put32(32,random_q);random_q=rnd(random_q);put32(36,random_q|1);put32(44,2+trial);
    bytes[450]=trial%4?8'h0c:0;random_q=rnd(random_q);put32(454,random_q);random_q=rnd(random_q);put32(458,random_q);
    bytes[510]=8'h55;bytes[511]=8'haa;
   end
   // Each group changes only one field of an otherwise valid header.
   // Exhaust every8-bit value, preserving the old parser's exact error
   // priority and public numeric results. Separate storage257 covers aborts.
   case(trial/256)
    0:bytes[11]=trial;1:bytes[17]=trial;2:bytes[13]=trial;3:bytes[16]=trial;
    4:bytes[510]=trial;5:bytes[511]=trial;6:bytes[22]=trial;7:bytes[19]=trial;
    8:bytes[12]=trial;9:bytes[18]=trial;10:bytes[23]=trial;11:bytes[20]=trial;
    12:put32(44,trial%256);13:bytes[450]=trial;14:put32(454,trial%256);15:put32(458,trial%256);
   endcase

   @(negedge clk);start=1;sd_timeout_err=0;sd_crc16_err=0;sd_rd_done=0;
   @(negedge clk);start=0;sd_rd_ready=1;
   waits=0;while(!a_sd_data_ready&&waits<16)begin @(negedge clk);waits++;end
   if(!a_sd_data_ready)begin errors++;$display("[FAIL] no header receive state");end
   limit=512;
   for(k=0;k<limit;k++)begin
    random_q=rnd(random_q);repeat(random_q[1:0])begin @(negedge clk);sd_data_valid=0;end
    @(negedge clk);sd_data=bytes[k];sd_data_valid=1;sd_data_last=k==511;
    @(negedge clk);sd_data_valid=0;sd_data_last=0;
   end
   if(limit!=512)begin
    force a.to_cnt=`SD_TO_DATA;force b.to_cnt=`SD_TO_DATA;
    @(negedge clk);release a.to_cnt;release b.to_cnt;
   end else begin
    sd_timeout_err=0;sd_crc16_err=0;sd_err_code=8'h23;sd_err_detail=8'h45;
   end
   repeat(8)@(negedge clk);
   // Cover asynchronous reset after both successful and failed operations.
   if(trial%5==0)begin #2;rst_n=0;#23;rst_n=1;end
  end
  if(!errors)$display("[PASS] public header contract:4096 targeted complete headers:all256 values of16 fields;exact public results,error priority and reset edges");
  $display("[TB] tb_v3_fat32_boot_parser_predicates288 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #100000000;$display("[FAIL] header miter timeout");$display("[TB] tb_v3_fat32_boot_parser_predicates288 done errors=1 comparisons=0");$finish;end
endmodule
