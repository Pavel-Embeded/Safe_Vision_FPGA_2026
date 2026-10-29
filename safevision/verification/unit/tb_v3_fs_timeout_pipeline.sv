`timescale 1ns/1ps
`include "safevision_defs.vh"
module tb_v3_fs_timeout_pipeline;
 reg  context_load=0;
 reg [135:0] context_in=0;
 reg  context_enable=0;
 reg  stream_enable=0;
 reg  clk=0;
 reg  rst_n=0;
 reg  start=0;
 reg [31:0] first_clus=0;
 reg [31:0] file_size=0;
 reg  ready=0;
 reg [7:0] sec_per_clus=0;
 reg [31:0] fat_start_lba=0;
 reg [31:0] data_start_lba=0;
 reg [31:0] total_clus=0;
 reg  wk_busy=0;
 reg  wk_done=0;
 reg [31:0] wk_next_clus=0;
 reg  wk_eoc=0;
 reg  wk_error=0;
 reg [7:0] wk_err_code=0;
 reg [7:0] wk_err_detail=0;
 reg  sd_rd_ready=0;
 reg [7:0] sd_data=0;
 reg  sd_data_valid=0;
 reg  sd_data_last=0;
 reg  sd_rd_done=0;
 reg  sd_timeout_err=0;
 reg  sd_crc16_err=0;
 reg [7:0] sd_err_code=0;
 reg [7:0] sd_err_detail=0;
 reg [31:0] external_lba=0;
 reg [31:0] external_timeout_count=0;
 reg  external_lba_valid=0;
 always #5 clk=~clk;
 integer errors=0,comparisons=0,data_errors=0,phase_errors=0;
 integer scenario,step,span;reg[31:0] seed_count,rng=32'h91cafe23;
 wire[31:0] phase_checks[0:3];integer total_phase_checks=0;
 genvar g;generate for(g=0;g<4;g=g+1)begin:lane
 localparam integer P=(g>=2),R=(g%2);
 integer sector_count=0,phase_count=0;reg[1:0] walker_pipe=0;
 assign phase_checks[g]=phase_count;
 wire [135:0] d_context_out,g_context_out;
 wire  d_idle_between_sectors,g_idle_between_sectors;
 wire  d_busy,g_busy;
 wire  d_done,g_done;
 wire  d_error,g_error;
 wire [7:0] d_err_code,g_err_code;
 wire [7:0] d_err_detail,g_err_detail;
 wire [31:0] d_bytes_rd,g_bytes_rd;
 wire [3:0] d_dbg_state,g_dbg_state;
 wire [7:0] d_data,g_data;
 wire  d_valid,g_valid;
 wire  d_sof,g_sof;
 wire  d_eof,g_eof;
 wire [31:0] d_wk_cur_clus,g_wk_cur_clus;
 wire  d_wk_start,g_wk_start;
 wire  d_wk_rst_walk,g_wk_rst_walk;
 wire [31:0] d_sd_rd_addr,g_sd_rd_addr;
 wire [15:0] d_sd_rd_len,g_sd_rd_len;
 wire  d_sd_rd_en,g_sd_rd_en;
 wire  d_sd_data_ready,g_sd_data_ready;
 wire [31:0] d_lba_cluster,g_lba_cluster;
 wire  d_timeout_tick,g_timeout_tick;
 wire  d_lba_request,g_lba_request;
v3_file_streamer_compact_ctx #(.EXTERNAL_LBA(P),.EXTERNAL_TIMER(P),.DIRECT_REQUEST_ADDRESS(P),.PIPELINED_LBA(P),.REGISTERED_TIMEOUT_EDGE(R)) dut(.context_load(context_load),.context_in(context_in),.context_out(d_context_out),.context_enable(context_enable),.stream_enable(stream_enable),.idle_between_sectors(d_idle_between_sectors),.clk(clk),.rst_n(rst_n),.start(start),.first_clus(first_clus),.file_size(file_size),.busy(d_busy),.done(d_done),.error(d_error),.err_code(d_err_code),.err_detail(d_err_detail),.bytes_rd(d_bytes_rd),.dbg_state(d_dbg_state),.data(d_data),.valid(d_valid),.ready(ready),.sof(d_sof),.eof(d_eof),.sec_per_clus(sec_per_clus),.fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),.total_clus(total_clus),.wk_cur_clus(d_wk_cur_clus),.wk_start(d_wk_start),.wk_rst_walk(d_wk_rst_walk),.wk_busy(wk_busy),.wk_done(walker_pipe[1]),.wk_next_clus(wk_next_clus),.wk_eoc(wk_eoc),.wk_error(wk_error),.wk_err_code(wk_err_code),.wk_err_detail(wk_err_detail),.sd_rd_addr(d_sd_rd_addr),.sd_rd_len(d_sd_rd_len),.sd_rd_en(d_sd_rd_en),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_ready(d_sd_data_ready),.sd_data_last((sector_count==511)),.sd_rd_done((sector_count==511&&d_sd_data_ready&&sd_data_valid)),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail),.external_lba(external_lba),.lba_cluster(d_lba_cluster),.external_timeout_count(external_timeout_count),.timeout_tick(d_timeout_tick),.external_lba_valid(external_lba_valid),.lba_request(d_lba_request));
v3_file_streamer_frozen_timeout #(.EXTERNAL_LBA(P),.EXTERNAL_TIMER(P),.DIRECT_REQUEST_ADDRESS(P),.PIPELINED_LBA(P)) gold(.context_load(context_load),.context_in(context_in),.context_out(g_context_out),.context_enable(context_enable),.stream_enable(stream_enable),.idle_between_sectors(g_idle_between_sectors),.clk(clk),.rst_n(rst_n),.start(start),.first_clus(first_clus),.file_size(file_size),.busy(g_busy),.done(g_done),.error(g_error),.err_code(g_err_code),.err_detail(g_err_detail),.bytes_rd(g_bytes_rd),.dbg_state(g_dbg_state),.data(g_data),.valid(g_valid),.ready(ready),.sof(g_sof),.eof(g_eof),.sec_per_clus(sec_per_clus),.fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),.total_clus(total_clus),.wk_cur_clus(g_wk_cur_clus),.wk_start(g_wk_start),.wk_rst_walk(g_wk_rst_walk),.wk_busy(wk_busy),.wk_done(walker_pipe[1]),.wk_next_clus(wk_next_clus),.wk_eoc(wk_eoc),.wk_error(wk_error),.wk_err_code(wk_err_code),.wk_err_detail(wk_err_detail),.sd_rd_addr(g_sd_rd_addr),.sd_rd_len(g_sd_rd_len),.sd_rd_en(g_sd_rd_en),.sd_rd_ready(sd_rd_ready),.sd_data(sd_data),.sd_data_valid(sd_data_valid),.sd_data_ready(g_sd_data_ready),.sd_data_last((sector_count==511)),.sd_rd_done((sector_count==511&&d_sd_data_ready&&sd_data_valid)),.sd_timeout_err(sd_timeout_err),.sd_crc16_err(sd_crc16_err),.sd_err_code(sd_err_code),.sd_err_detail(sd_err_detail),.external_lba(external_lba),.lba_cluster(g_lba_cluster),.external_timeout_count(external_timeout_count),.timeout_tick(g_timeout_tick),.external_lba_valid(external_lba_valid),.lba_request(g_lba_request));
 wire[320:0] d_public={d_context_out,d_idle_between_sectors,d_busy,d_done,d_error,d_err_code,d_err_detail,d_bytes_rd,d_dbg_state,d_data,d_valid,d_sof,d_eof,d_wk_cur_clus,d_wk_start,d_wk_rst_walk,d_sd_rd_addr,d_sd_rd_len,d_sd_rd_en,d_sd_data_ready,d_lba_cluster,d_timeout_tick,d_lba_request};
 wire[320:0] g_public={g_context_out,g_idle_between_sectors,g_busy,g_done,g_error,g_err_code,g_err_detail,g_bytes_rd,g_dbg_state,g_data,g_valid,g_sof,g_eof,g_wk_cur_clus,g_wk_start,g_wk_rst_walk,g_sd_rd_addr,g_sd_rd_len,g_sd_rd_en,g_sd_data_ready,g_lba_cluster,g_timeout_tick,g_lba_request};
 always @(posedge clk)begin
  if(!rst_n||context_load)begin sector_count<=0;walker_pipe<=0;end
  else begin
   walker_pipe<={walker_pipe[0],d_wk_start};
   if(d_sd_rd_en)sector_count<=0;
   else if(sd_data_valid&&d_sd_data_ready)sector_count<=(sector_count==511)?0:sector_count+1;
  end
  if(rst_n&&R&&stream_enable&&context_enable&&dut.bcnt==511&&!dut.valid&&sd_data_valid&&d_sd_data_ready&&!dut.stop_pending)begin
   phase_count=phase_count+1;
   if(dut.timeout_last_q!==dut.last_file_byte)begin phase_errors=phase_errors+1;errors=errors+1;if(phase_errors<=4)$display("[FAIL] sector-boundary predicate is stale lane=%0d",g);end
  end
  if(rst_n)begin
   comparisons=comparisons+1;
   if(d_public!==g_public)begin data_errors=data_errors+1;errors=errors+1;if(data_errors<=6)$display("[FAIL] full file-streamer public interface differs at consumption edge lane=%0d case=%0d step=%0d",g,scenario,step);end
  end
  #1;
  if(rst_n)begin
   comparisons=comparisons+1;
   if(d_public!==g_public)begin data_errors=data_errors+1;errors=errors+1;if(data_errors<=6)$display("[FAIL] full file-streamer public interface differs lane=%0d case=%0d step=%0d",g,scenario,step);end
  end
 end
 end endgenerate
 task reset_all;begin @(negedge clk);rst_n=0;start=0;context_load=0;repeat(3)@(negedge clk);rst_n=1;end endtask
 initial begin
  ready=1;stream_enable=1;context_enable=1;sd_rd_ready=1;sd_data_valid=1;external_lba_valid=1;external_lba=128;
  first_clus=2;sec_per_clus=4;fat_start_lba=8;data_start_lba=128;total_clus=65536;wk_next_clus=3;
  wk_err_code=8'h03;wk_err_detail=8'h37;sd_err_code=8'h03;sd_err_detail=8'h37;
  reset_all;
  for(scenario=0;scenario<256;scenario=scenario+1)begin
   case(scenario%8)0:span=0;1:span=1;2:span=511;3:span=512;4:span=513;5:span=1024;6:span=1025;default:span=2049;endcase
   case((scenario/8)%4)0:seed_count=0;1:seed_count=32'hfffffe00;2:seed_count=32'hffffffff;default:seed_count=32'h12345678;endcase
   if((scenario%5)==0)begin reset_all;file_size=span;start=1;end
   else begin @(negedge clk);context_in={32'd2,32'd128,8'd0,seed_count,seed_count+span};context_load=1;end
   @(negedge clk);start=0;context_load=0;
   for(step=0;step<4000;step=step+1)begin
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    ready=(rng[2:0]!=0);sd_data_valid=(rng[5:3]!=0);sd_data=rng[15:8];
    stream_enable=(rng[7:6]!=0);context_enable=(rng[9:8]!=0);
    external_timeout_count=((scenario%11)==0&&step==500)?`SD_TO_DATA:0;
    sd_crc16_err=((scenario%17)==0&&step==300);sd_timeout_err=((scenario%19)==0&&step==700);
    wk_eoc=(scenario%13)==0;wk_error=(scenario%23)==0;
    @(negedge clk);
   end
   sd_crc16_err=0;sd_timeout_err=0;external_timeout_count=0;stream_enable=1;context_enable=1;
  end
  for(step=0;step<4;step=step+1)begin total_phase_checks=total_phase_checks+phase_checks[step];$display("[COVER] lane=%0d sector_predicate_checks=%0d",step,phase_checks[step]);end
  if(phase_checks[1]<32||phase_checks[3]<32)begin errors=errors+1;$display("[FAIL] missing reachable sector-boundary coverage");end
  if(errors==0)$display("[PASS] complete frozen public file-streamer interface; four profiles, arbitrary contexts, count wrap, EOF, backpressure and SD faults");
  $display("PASS tb_v3_fs_timeout_pipeline errors=%0d comparisons=%0d data_errors=%0d phase_errors=%0d driver_errors=0 cases=256",errors,comparisons,data_errors,phase_errors);$finish;
 end
endmodule
