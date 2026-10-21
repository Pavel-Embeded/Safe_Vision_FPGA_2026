`timescale 1ns/1ps
module tb_v3_file_lba_equivalence;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 integer errors=0,comparisons=0,k,j;reg[31:0]rng=32'hfa261801;
 function[31:0]rand32;begin rng=rng*1664525+1013904223;rand32=rng;end endfunction
 reg  context_load=0;
 reg [135:0] context_in=0;
 wire [135:0] a_context_out,b_context_out;
 reg  context_enable=0;
 reg  stream_enable=0;
 wire  a_idle_between_sectors,b_idle_between_sectors;
 reg  start=0;
 reg [31:0] first_clus=0;
 reg [31:0] file_size=0;
 wire  a_busy,b_busy;
 wire  a_done,b_done;
 wire  a_error,b_error;
 wire [7:0] a_err_code,b_err_code;
 wire [7:0] a_err_detail,b_err_detail;
 wire [31:0] a_bytes_rd,b_bytes_rd;
 wire [3:0] a_dbg_state,b_dbg_state;
 wire [7:0] a_data,b_data;
 wire  a_valid,b_valid;
 reg  ready=0;
 wire  a_sof,b_sof;
 wire  a_eof,b_eof;
 reg [7:0] sec_per_clus=0;
 reg [31:0] fat_start_lba=0;
 reg [31:0] data_start_lba=0;
 reg [31:0] total_clus=0;
 wire [31:0] a_wk_cur_clus,b_wk_cur_clus;
 wire  a_wk_start,b_wk_start;
 wire  a_wk_rst_walk,b_wk_rst_walk;
 reg  wk_busy=0;
 reg  wk_done=0;
 reg [31:0] wk_next_clus=0;
 reg  wk_eoc=0;
 reg  wk_error=0;
 reg [7:0] wk_err_code=0;
 reg [7:0] wk_err_detail=0;
 wire [31:0] a_sd_rd_addr,b_sd_rd_addr;
 wire [15:0] a_sd_rd_len,b_sd_rd_len;
 wire  a_sd_rd_en,b_sd_rd_en;
 reg  sd_rd_ready=0;
 reg [7:0] sd_data=0;
 reg  sd_data_valid=0;
 wire  a_sd_data_ready,b_sd_data_ready;
 reg  sd_data_last=0;
 reg  sd_rd_done=0;
 reg  sd_timeout_err=0;
 reg  sd_crc16_err=0;
 reg [7:0] sd_err_code=0;
 reg [7:0] sd_err_detail=0;
 v3_file_streamer_compact_ctx a(.context_load(context_load),.context_in(context_in),.context_out(a_context_out),.context_enable(context_enable),.stream_enable(stream_enable),.idle_between_sectors(a_idle_between_sectors),.clk(clk),.rst_n(rst_n),.start(start),.first_clus(first_clus),.file_size(file_size),.busy(a_busy),.done(a_done),.error(a_error),.err_code(a_err_code),.err_detail(a_err_detail),.bytes_rd(a_bytes_rd),.dbg_state(a_dbg_state),.data(a_data),.valid(a_valid),.ready(ready),.sof(a_sof),.eof(a_eof),.sec_per_clus(sec_per_clus),.fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),.total_clus(total_clus),.wk_cur_clus(a_wk_cur_clus),.wk_start(a_wk_start),.wk_rst_walk(a_wk_rst_walk),.wk_busy(wk_busy),.wk_done(wk_done),.wk_next_clus(wk_next_clus),.wk_eoc(wk_eoc),.wk_error(wk_error),.wk_err_code(wk_err_code),.wk_err_detail(wk_err_detail),.sd_rd_addr(a_sd_rd_addr),.sd_rd_len(a_sd_rd_len),.sd_rd_en(a_sd_rd_en),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_ready(a_sd_data_ready),.sd_data_last(sd_data_last),.sd_rd_done(sd_rd_done),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail));
 v3_file_streamer_compact_reference b(.context_load(context_load),.context_in(context_in),.context_out(b_context_out),.context_enable(context_enable),.stream_enable(stream_enable),.idle_between_sectors(b_idle_between_sectors),.clk(clk),.rst_n(rst_n),.start(start),.first_clus(first_clus),.file_size(file_size),.busy(b_busy),.done(b_done),.error(b_error),.err_code(b_err_code),.err_detail(b_err_detail),.bytes_rd(b_bytes_rd),.dbg_state(b_dbg_state),.data(b_data),.valid(b_valid),.ready(ready),.sof(b_sof),.eof(b_eof),.sec_per_clus(sec_per_clus),.fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),.total_clus(total_clus),.wk_cur_clus(b_wk_cur_clus),.wk_start(b_wk_start),.wk_rst_walk(b_wk_rst_walk),.wk_busy(wk_busy),.wk_done(wk_done),.wk_next_clus(wk_next_clus),.wk_eoc(wk_eoc),.wk_error(wk_error),.wk_err_code(wk_err_code),.wk_err_detail(wk_err_detail),.sd_rd_addr(b_sd_rd_addr),.sd_rd_len(b_sd_rd_len),.sd_rd_en(b_sd_rd_en),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_ready(b_sd_data_ready),.sd_data_last(sd_data_last),.sd_rd_done(sd_rd_done),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail));
 always@(posedge clk)begin #1;if(rst_n)begin comparisons++;if({a_context_out,a_idle_between_sectors,a_busy,a_done,a_error,a_err_code,a_err_detail,a_bytes_rd,a_dbg_state,a_data,a_valid,a_sof,a_eof,a_wk_cur_clus,a_wk_start,a_wk_rst_walk,a_sd_rd_addr,a_sd_rd_len,a_sd_rd_en,a_sd_data_ready}!=={b_context_out,b_idle_between_sectors,b_busy,b_done,b_error,b_err_code,b_err_detail,b_bytes_rd,b_dbg_state,b_data,b_valid,b_sof,b_eof,b_wk_cur_clus,b_wk_start,b_wk_rst_walk,b_sd_rd_addr,b_sd_rd_len,b_sd_rd_en,b_sd_data_ready})begin errors++;if(errors<12)$display("[FAIL] complete public file-stream/context interface at cycle%0d",comparisons);end end end
 initial begin
 repeat(4)@(negedge clk);rst_n=1;context_enable=1;stream_enable=1;
 // Empty-file starts isolate LBA algebra over all256 SPC encodings and
 // arbitrary32-bit cluster/base values, including modular wrap and invalid SPC.
 for(k=0;k<65536;k++)begin
  first_clus=rand32();data_start_lba=rand32();sec_per_clus=k%256;file_size=0;
  case(k%8)0:first_clus=0;1:first_clus=1;2:first_clus=2;3:first_clus=32'hffffffff;default:;endcase
  start=1;@(negedge clk);start=0;repeat(3)@(negedge clk);
 end
 // Complete stream state machine under backpressure, fragmented WALK results,
 // transaction errors, legal/illegal contexts and intentional service pauses.
 for(k=0;k<400000;k++)begin
  first_clus=rand32();
  ready=rand32();
  fat_start_lba=rand32();
  data_start_lba=rand32();
  total_clus=rand32();
  wk_busy=rand32();
  wk_done=rand32();
  wk_next_clus=rand32();
  wk_eoc=rand32();
  wk_err_code=rand32();
  wk_err_detail=rand32();
  sd_rd_ready=rand32();
  sd_data=rand32();
  sd_data_valid=rand32();
  sd_data_last=rand32();
  sd_rd_done=rand32();
  sd_err_code=rand32();
  sd_err_detail=rand32();
  ready=(rand32()%4)!=0;sd_data_valid=(rand32()%4)!=0;sd_rd_ready=1;
  wk_done=(rand32()%8)==0;wk_eoc=(rand32()%128)==0;
  wk_error=(rand32()%1024)==0;sd_timeout_err=(rand32()%4096)==0;sd_crc16_err=(rand32()%4096)==0;
  context_enable=(rand32()%16)!=0;stream_enable=(rand32()%8)!=0;
  context_load=k%10007==0;context_in={rand32(),rand32(),8'd0,32'd0,32'd2048};
  file_size=(k%13==0)?0:2048;start=!a_busy;
  if(k%8192==0)sec_per_clus=1<<(k/8192%8);
  @(negedge clk);
 end
 if(errors==0)$display("[PASS] all256SPC,65536 modular starts,400000 complete stream/context stress cycles, exact public pins");
 $display("[TB] tb_v3_file_lba_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
