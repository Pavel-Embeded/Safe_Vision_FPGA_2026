`include "safevision_defs.vh"
module tb_v3_mbr_parser_storage257;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,start=0,sd_rd_ready=0,sd_data_valid=0,sd_data_last=0,sd_rd_done=0,sd_timeout_err=0,sd_crc16_err=0;
 reg[7:0]sd_data=0,sd_err_code=0,sd_err_detail=0;reg[7:0] bytes[0:511];
 integer errors=0,comparisons=0,trial,k,j,limit,waits;reg[31:0]random_q=32'h71a22384;reg[31:0]v;
 function[31:0]rnd(input[31:0]a);reg[31:0]b;begin begin b=a^(a<<13);b=b^(b>>17);rnd=b^(b<<5);end  end endfunction
 wire[0:0] a_parse_done;
 wire[0:0] b_parse_done;
 wire[0:0] a_has_mbr;
 wire[0:0] b_has_mbr;
 wire[31:0] a_vol_base_lba;
 wire[31:0] b_vol_base_lba;
 wire[31:0] a_part_secs;
 wire[31:0] b_part_secs;
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
mbr_parser a(.clk(clk),.rst_n(rst_n),.start(start),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_last(sd_data_last),.sd_rd_done(sd_rd_done),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail),.parse_done(a_parse_done),.has_mbr(a_has_mbr),.vol_base_lba(a_vol_base_lba),.part_secs(a_part_secs),.sd_rd_addr(a_sd_rd_addr),.sd_rd_len(a_sd_rd_len),.sd_rd_en(a_sd_rd_en),.sd_data_ready(a_sd_data_ready),.err_code(a_err_code),.err_detail(a_err_detail),.dbg_state(a_dbg_state));
mbr_parser255_reference b(.clk(clk),.rst_n(rst_n),.start(start),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_last(sd_data_last),.sd_rd_done(sd_rd_done),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail),.parse_done(b_parse_done),.has_mbr(b_has_mbr),.vol_base_lba(b_vol_base_lba),.part_secs(b_part_secs),.sd_rd_addr(b_sd_rd_addr),.sd_rd_len(b_sd_rd_len),.sd_rd_en(b_sd_rd_en),.sd_data_ready(b_sd_data_ready),.err_code(b_err_code),.err_detail(b_err_detail),.dbg_state(b_dbg_state));
 always @(posedge clk)begin #1;comparisons = comparisons + 1;if({a_parse_done,a_has_mbr,a_vol_base_lba,a_part_secs,a_sd_rd_addr,a_sd_rd_len,a_sd_rd_en,a_sd_data_ready,a_err_code,a_err_detail,a_dbg_state}!=={b_parse_done,b_has_mbr,b_vol_base_lba,b_part_secs,b_sd_rd_addr,b_sd_rd_len,b_sd_rd_en,b_sd_data_ready,b_err_code,b_err_detail,b_dbg_state})begin errors = errors + 1;if(errors<8)$display("[FAIL] all-public-pin mismatch at%0t trial%0d byte%0d",$time,trial,k);end end
 task put32(input integer pos,input[31:0]n);begin begin begin : v_loop_1 integer q; for( q=0;q<4;q = q + 1)bytes[pos+q]=n>>(8*q); end end  end endtask
 initial begin
  #27;rst_n=1;
  for(trial=0;trial<1024;trial = trial + 1)begin
   for(k=0;k<512;k = k + 1)begin random_q=rnd(random_q);bytes[k]=random_q;end


   if(trial%3!=1)begin
    bytes[11]=0;bytes[12]=2;bytes[13]=1<<(trial%8);bytes[14]=32;bytes[15]=0;bytes[16]=1+trial%2;
    bytes[17]=0;bytes[18]=0;bytes[19]=0;bytes[20]=0;bytes[22]=0;bytes[23]=0;
    random_q=rnd(random_q);put32(32,random_q);random_q=rnd(random_q);put32(36,random_q|1);put32(44,2+trial);
    bytes[450]=trial%4 ? 8'h0c:0;random_q=rnd(random_q);put32(454,random_q);random_q=rnd(random_q);put32(458,random_q);
    bytes[510]=8'h55;bytes[511]=8'haa;
   end
   @(negedge clk);start=1;sd_timeout_err=0;sd_crc16_err=0;sd_rd_done=0;
   @(negedge clk);start=0;sd_rd_ready=1;
   waits=0;while(!a_sd_data_ready&&waits<16)begin @(negedge clk);waits = waits + 1;end
   if(!a_sd_data_ready)begin errors = errors + 1;$display("[FAIL] no header receive state");end
   limit=trial%7==0 ? 100:512;
   for(k=0;k<limit;k = k + 1)begin
    random_q=rnd(random_q);repeat(random_q[1:0])begin @(negedge clk);sd_data_valid=0;end
    @(negedge clk);sd_data=bytes[k];sd_data_valid=1;sd_data_last=k==511;
    @(negedge clk);sd_data_valid=0;sd_data_last=0;
   end
   if(limit!=512)begin
    force a.to_cnt=`SD_TO_DATA;force b.to_cnt=`SD_TO_DATA;
    @(negedge clk);release a.to_cnt;release b.to_cnt;
   end else begin
    sd_timeout_err=trial%11==1;sd_crc16_err=trial%13==1;sd_err_code=8'h23;sd_err_detail=8'h45;
   end
   repeat(8)@(negedge clk);

   if(trial%5==0)begin #2;rst_n=0;#23;rst_n=1;end
  end
  if(!errors)$display("[PASS] public header contract:1024 complete/invalid/aborted/reset epochs;field assembly and status edges");
  $display("[TB] tb_v3_mbr_parser_storage257 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #100000000;$display("[FAIL] header miter timeout");$display("[TB] tb_v3_mbr_parser_storage257 done errors=1 comparisons=0");$finish;end
endmodule
