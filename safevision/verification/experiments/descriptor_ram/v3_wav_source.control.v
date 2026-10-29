


module v3_wav_source #(parameter integer EXTERNAL_SERVICE=0)(input wire clk,rst_n,mounted,cache_ready,
 input wire [63:0] cache_keys,input wire [7:0] sec_per_clus,
 input wire [31:0] fat_start_lba,data_start_lba,root_dir_lba,root_clus,total_clus,
 input wire [3:0] slot_fill,sector_room,
 output wire [127:0] pcm_data,output wire [3:0] pcm_valid,input wire [3:0] pcm_ready,
 output reg index_done,output reg [3:0] fallback,output reg [3:0] found,
 output wire rd_en,output wire [31:0] rd_addr,output wire [15:0] rd_len,
 input wire rd_ready,input wire [7:0] data,input wire data_valid,
 output wire data_ready,input wire data_last,rd_done,timeout_err,crc16_err,
 input wire [7:0] err_code,err_detail,
 input wire external_service_ready,output wire[444:0] core_cmd,input wire[836:0] core_rsp);


 localparam FS_BITS=136,WP_BITS=111,CTX_BITS=FS_BITS+WP_BITS+32;
 localparam CTX_WORDS=(CTX_BITS+15)/16,CTX_PAD=CTX_WORDS*16;
 localparam Q_SCAN=0,Q_CHOOSE=1,Q_RESET=2,Q_START=3,Q_RUN=4,Q_SAVE0=5,Q_SAVE=6,
            Q_LOAD1=7,Q_LOAD2=8,Q_APPLY=9;
 reg [3:0] state;reg kernel_progress;reg [1:0] active,rr;reg [3:0] saved;
 reg [31:0] track_clus[0:3],track_size[0:3];reg scan_start,scan_seen;
 wire scan_done,dir_bad;wire [7:0] scan_code;wire [87:0] name;wire [31:0] fc,size;wire ev;
 wire valid_name=name[87:72]==16'h5356&&name[39:24]==16'h2020&&name[23:0]==24'h574156&&
 name[71:64]>=8'h30&&name[71:64]<=8'h39&&name[63:56]>=8'h30&&name[63:56]<=8'h39&&
 name[55:48]>=8'h30&&name[55:48]<=8'h39&&name[47:40]>=8'h30&&name[47:40]<=8'h39;
 wire [15:0] key={name[67:64],name[59:56],name[51:48],name[43:40]};
 wire kernel_rst_n=rst_n&&state!=Q_RESET;
 wire start=state==Q_START,load_context=(state==Q_LOAD2||state==Q_SAVE);
 wire [FS_BITS-1:0] fs_context;wire [WP_BITS-1:0] wp_context;
 reg [CTX_PAD-CTX_BITS-1:0] context_padding;
 reg [5:0] context_index;wire [15:0] context_q;
 wire [7:0] context_address=active*CTX_WORDS+context_index;
 wire [2:0] en,ready,dr,dv,dl,done,toerr,crcerr;
 wire [31:0] addr[0:2];wire [15:0] lens[0:2];wire [3:0] states[0:2];
 wire [31:0] scan_cur,file_cur,w_next,hop_count;
 wire scan_ws,scan_wr,file_ws,file_wr,wb,wd,we,w_eoc;wire [7:0] wc,wt;
 wire [7:0] bytes_data;wire fvalid,fend,fbusy,fdone,ferr,waverr,pauseable,parser_ready;
 wire [31:0] sample;wire sample_valid;
 wire pause_boundary=state==Q_RUN&&kernel_progress&&pauseable&&!fvalid&&!sample_valid;
 wire run_kernel=(state==Q_RUN||state==Q_START)&&!pause_boundary;

 wire [CTX_PAD-1:0] export_context={context_padding,hop_count,fs_context,wp_context};
 wire [CTX_PAD-1:0] next_context={(state==Q_SAVE) ? export_context[15:0]:context_q,export_context[CTX_PAD-1:16]};
 wire [15:0] save_word=export_context[15:0];

 a_pixel_fifo_eram #(.MODE("SP"),.DATAWIDTH_A(16),.DATAWIDTH_B(16),
 .ADDRWIDTH_A(8),.ADDRWIDTH_B(8),.REGMODE_A("NOREG")) context_ram(
 .clka(clk),.rsta(!rst_n),.cea(state==Q_SAVE||state==Q_LOAD1),.ocea(1'b1),.wea(state==Q_SAVE),
 .dia(save_word),.addra(context_address),.doa(context_q),
 .clkb(clk),.rstb(!rst_n),.ceb(1'b0),.oceb(1'b0),.web(1'b0),.dib(16'd0),.addrb(8'd0),.dob());
 assign pcm_data={128'd0}|({96'd0,sample}<<(active*32));
 assign pcm_valid=(state==Q_RUN) ? (sample_valid ? (4'b1<<active):4'b0):4'b0;
 reg [1:0] chosen;reg eligible;integer i,j,k;
 always @*begin eligible=0;chosen=0;
  for(i=0;i<4;i=i+1)begin j=rr+i;if(j>=4)j=j-4;
   if(!eligible&&found[j]&&!fallback[j]&&slot_fill[j]&&sector_room[j])begin eligible=1;chosen=j;end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=Q_SCAN;kernel_progress<=0;active<=0;rr<=0;saved<=0;context_padding<=0;context_index<=0;
   scan_start<=0;scan_seen<=0;index_done<=0;fallback<=0;found<=0;
   for(k=0;k<4;k=k+1)begin track_clus[k]<=0;track_size[k]<=0;end
  end else begin
   scan_start<=0;
   if(!scan_seen&&mounted&&cache_ready&&(!EXTERNAL_SERVICE||external_service_ready))begin scan_seen<=1;scan_start<=1;end
   if(ev&&valid_name&&!index_done)for(k=0;k<4;k=k+1)
    if(key==cache_keys[k*16+:16]&&!found[k]&&fc>=2&&size>=44)begin
     found[k]<=1;track_clus[k]<=fc;track_size[k]<=size;end
   case(state)
    Q_SCAN:if(scan_seen&&scan_done)begin
     index_done<=1;fallback<=(dir_bad||scan_code!=0) ? 4'hf:~found;state<=Q_CHOOSE;
    end
    Q_CHOOSE:if(eligible)begin kernel_progress<=0;active<=chosen;rr<=chosen+1'b1;context_index<=0;
     if(saved[chosen])state<=Q_LOAD1;else state<=Q_RESET;
    end
    Q_RESET:begin context_padding<=0;state<=Q_START;end
    Q_START:state<=Q_RUN;
    Q_RUN:begin
     if(fvalid&&(parser_ready||waverr))kernel_progress<=1;
     if(waverr||ferr)fallback[active]<=1;

     if((fdone&&!fbusy&&!sample_valid)||((waverr||ferr)&&pauseable&&!fvalid&&!sample_valid))begin
      saved[active]<=0;state<=Q_CHOOSE;
     end else if(kernel_progress&&pauseable&&!fvalid&&!sample_valid)state<=Q_SAVE0;
    end
    Q_SAVE0:begin context_index<=0;state<=Q_SAVE;end
    Q_SAVE:begin
     context_padding<=next_context[CTX_PAD-1:CTX_BITS];
     if(context_index==CTX_WORDS-1)begin saved[active]<=1;state<=Q_CHOOSE;end
     else context_index<=context_index+1'b1;
    end
    Q_LOAD1:state<=Q_LOAD2;
    Q_LOAD2:begin context_padding<=next_context[CTX_PAD-1:CTX_BITS];
     if(context_index==CTX_WORDS-1)state<=Q_APPLY;
     else begin context_index<=context_index+1'b1;state<=Q_LOAD1;end
    end
    Q_APPLY:state<=Q_RUN;
    default:state<=Q_SCAN;
   endcase
  end
 end
wire svc_d_scan_done;
wire svc_d_dir_bad;
wire [7:0] svc_d_err_code;
wire [7:0] svc_d_err_detail;
wire [3:0] svc_d_dbg_state;
wire [87:0] svc_d_ent_name;
wire [7:0] svc_d_ent_attr;
wire [31:0] svc_d_ent_first_clus;
wire [31:0] svc_d_ent_size;
wire [15:0] svc_d_ent_index;
wire svc_d_ent_valid;
wire [31:0] svc_d_sd_rd_addr;
wire [15:0] svc_d_sd_rd_len;
wire svc_d_sd_rd_en;
wire svc_d_sd_data_ready;
wire [31:0] svc_d_wk_cur_clus;
wire svc_d_wk_start;
wire svc_d_wk_rst_walk;
wire svc_f_busy;
wire svc_f_done;
wire svc_f_error;
wire [7:0] svc_f_err_code;
wire [7:0] svc_f_err_detail;
wire [31:0] svc_f_bytes_rd;
wire [3:0] svc_f_dbg_state;
wire [7:0] svc_f_data;
wire svc_f_valid;
wire svc_f_sof;
wire svc_f_eof;
wire svc_f_idle_between_sectors;
wire [264:0] svc_f_context_out;
wire [31:0] svc_f_sd_rd_addr;
wire [15:0] svc_f_sd_rd_len;
wire svc_f_sd_rd_en;
wire svc_f_sd_data_ready;
wire [31:0] svc_f_wk_cur_clus;
wire svc_f_wk_start;
wire svc_f_wk_rst_walk;
wire svc_w_busy;
wire svc_w_done;
wire [31:0] svc_w_next_clus;
wire svc_w_eoc;
wire svc_w_error;
wire [7:0] svc_w_err_code;
wire [7:0] svc_w_err_detail;
wire [31:0] svc_w_hop_cnt;
wire [3:0] svc_w_dbg_state;
wire [31:0] svc_w_sd_rd_addr;
wire [15:0] svc_w_sd_rd_len;
wire svc_w_sd_rd_en;
wire svc_w_sd_data_ready;
assign {svc_d_scan_done,svc_d_dir_bad,svc_d_err_code,svc_d_err_detail,svc_d_dbg_state,svc_d_ent_name,svc_d_ent_attr,svc_d_ent_first_clus,svc_d_ent_size,svc_d_ent_index,svc_d_ent_valid,svc_d_sd_rd_addr,svc_d_sd_rd_len,svc_d_sd_rd_en,svc_d_sd_data_ready,svc_d_wk_cur_clus,svc_d_wk_start,svc_d_wk_rst_walk,svc_f_busy,svc_f_done,svc_f_error,svc_f_err_code,svc_f_err_detail,svc_f_bytes_rd,svc_f_dbg_state,svc_f_data,svc_f_valid,svc_f_sof,svc_f_eof,svc_f_idle_between_sectors,svc_f_context_out,svc_f_sd_rd_addr,svc_f_sd_rd_len,svc_f_sd_rd_en,svc_f_sd_data_ready,svc_f_wk_cur_clus,svc_f_wk_start,svc_f_wk_rst_walk,svc_w_busy,svc_w_done,svc_w_next_clus,svc_w_eoc,svc_w_error,svc_w_err_code,svc_w_err_detail,svc_w_hop_cnt,svc_w_dbg_state,svc_w_sd_rd_addr,svc_w_sd_rd_len,svc_w_sd_rd_en,svc_w_sd_data_ready}=core_rsp;

 wire legacy_ds_scan_done;
assign scan_done=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_scan_done:1'd0):legacy_ds_scan_done;
wire legacy_ds_dir_bad;
assign dir_bad=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_dir_bad:1'd0):legacy_ds_dir_bad;
wire [7:0] legacy_ds_err_code;
assign scan_code=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_err_code:8'd0):legacy_ds_err_code;
wire [3:0] legacy_ds_dbg_state;
assign states[0]=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_dbg_state:4'd0):legacy_ds_dbg_state;
wire [87:0] legacy_ds_ent_name;
assign name=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_ent_name:88'd0):legacy_ds_ent_name;
wire [31:0] legacy_ds_ent_first_clus;
assign fc=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_ent_first_clus:32'd0):legacy_ds_ent_first_clus;
wire [31:0] legacy_ds_ent_size;
assign size=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_ent_size:32'd0):legacy_ds_ent_size;
wire legacy_ds_ent_valid;
assign ev=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_ent_valid:1'd0):legacy_ds_ent_valid;
wire [31:0] legacy_ds_sd_rd_addr;
assign addr[0]=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_sd_rd_addr:32'd0):legacy_ds_sd_rd_addr;
wire [15:0] legacy_ds_sd_rd_len;
assign lens[0]=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_sd_rd_len:16'd0):legacy_ds_sd_rd_len;
wire legacy_ds_sd_rd_en;
assign en[0]=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_sd_rd_en:1'd0):legacy_ds_sd_rd_en;
wire legacy_ds_sd_data_ready;
assign dr[0]=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_sd_data_ready:1'd0):legacy_ds_sd_data_ready;
wire [31:0] legacy_ds_wk_cur_clus;
assign scan_cur=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_wk_cur_clus:32'd0):legacy_ds_wk_cur_clus;
wire legacy_ds_wk_start;
assign scan_ws=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_wk_start:1'd0):legacy_ds_wk_start;
wire legacy_ds_wk_rst_walk;
assign scan_wr=EXTERNAL_SERVICE ? (external_service_ready ? svc_d_wk_rst_walk:1'd0):legacy_ds_wk_rst_walk;
fat32_directory_scanner ds(.clk(clk),.rst_n(EXTERNAL_SERVICE ? 1'b0:rst_n),.scan_en(scan_start),.scan_done(legacy_ds_scan_done),.dir_bad(legacy_ds_dir_bad),.err_code(legacy_ds_err_code),
 .dbg_state(legacy_ds_dbg_state),.sec_per_clus(sec_per_clus),.root_clus(root_clus),.root_dir_lba(root_dir_lba),.data_start_lba(data_start_lba),
 .ent_name(legacy_ds_ent_name),.ent_first_clus(legacy_ds_ent_first_clus),.ent_size(legacy_ds_ent_size),.ent_valid(legacy_ds_ent_valid),.ent_ready(1'b1),
 .sd_rd_addr(legacy_ds_sd_rd_addr),.sd_rd_len(legacy_ds_sd_rd_len),.sd_rd_en(legacy_ds_sd_rd_en),.sd_rd_ready(ready[0]),
 .sd_data(data),.sd_data_valid(dv[0]),.sd_data_ready(legacy_ds_sd_data_ready),.sd_data_last(dl[0]),.sd_rd_done(done[0]),
 .sd_timeout_err(toerr[0]),.sd_crc16_err(crcerr[0]),.sd_err_code(err_code),.sd_err_detail(err_detail),
 .wk_cur_clus(legacy_ds_wk_cur_clus),.wk_start(legacy_ds_wk_start),.wk_rst_walk(legacy_ds_wk_rst_walk),.wk_busy(wb),.wk_done(wd),
 .wk_next_clus(w_next),.wk_eoc(w_eoc),.wk_error(we),.wk_err_code(wc),.wk_err_detail(wt));
 wire legacy_wk_busy;
assign wb=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_busy:1'd0):legacy_wk_busy;
wire legacy_wk_done;
assign wd=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_done:1'd0):legacy_wk_done;
wire [31:0] legacy_wk_next_clus;
assign w_next=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_next_clus:32'd0):legacy_wk_next_clus;
wire legacy_wk_eoc;
assign w_eoc=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_eoc:1'd0):legacy_wk_eoc;
wire legacy_wk_error;
assign we=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_error:1'd0):legacy_wk_error;
wire [7:0] legacy_wk_err_code;
assign wc=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_err_code:8'd0):legacy_wk_err_code;
wire [7:0] legacy_wk_err_detail;
assign wt=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_err_detail:8'd0):legacy_wk_err_detail;
wire [31:0] legacy_wk_hop_cnt;
assign hop_count=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_hop_cnt:32'd0):legacy_wk_hop_cnt;
wire [3:0] legacy_wk_dbg_state;
assign states[2]=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_dbg_state:4'd0):legacy_wk_dbg_state;
wire [31:0] legacy_wk_sd_rd_addr;
assign addr[2]=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_sd_rd_addr:32'd0):legacy_wk_sd_rd_addr;
wire [15:0] legacy_wk_sd_rd_len;
assign lens[2]=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_sd_rd_len:16'd0):legacy_wk_sd_rd_len;
wire legacy_wk_sd_rd_en;
assign en[2]=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_sd_rd_en:1'd0):legacy_wk_sd_rd_en;
wire legacy_wk_sd_data_ready;
assign dr[2]=EXTERNAL_SERVICE ? (external_service_ready ? svc_w_sd_data_ready:1'd0):legacy_wk_sd_data_ready;
v3_cluster_walker_ctx wk(.clk(clk),.rst_n(EXTERNAL_SERVICE ? 1'b0:kernel_rst_n),.context_load(load_context),
 .context_hop(next_context[WP_BITS+FS_BITS+:32]),.rst_walk(index_done ? (run_kernel&&file_wr):scan_wr),.start(index_done ? (run_kernel&&file_ws):scan_ws),
 .cur_clus(index_done ? file_cur:scan_cur),.busy(legacy_wk_busy),.done(legacy_wk_done),.next_clus(legacy_wk_next_clus),.hop_cnt(legacy_wk_hop_cnt),
 .eoc(legacy_wk_eoc),.error(legacy_wk_error),.err_code(legacy_wk_err_code),.err_detail(legacy_wk_err_detail),.dbg_state(legacy_wk_dbg_state),
 .fat_start_lba(fat_start_lba),.total_clus(total_clus),.sd_rd_addr(legacy_wk_sd_rd_addr),.sd_rd_len(legacy_wk_sd_rd_len),.sd_rd_en(legacy_wk_sd_rd_en),.sd_rd_ready(ready[2]),
 .sd_data(data),.sd_data_valid(dv[2]),.sd_data_ready(legacy_wk_sd_data_ready),.sd_data_last(dl[2]),.sd_rd_done(done[2]),
 .sd_timeout_err(toerr[2]),.sd_crc16_err(crcerr[2]),.sd_err_code(err_code),.sd_err_detail(err_detail));
 wire legacy_fs_busy;
assign fbusy=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_busy:1'd0):legacy_fs_busy;
wire legacy_fs_done;
assign fdone=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_done:1'd0):legacy_fs_done;
wire legacy_fs_error;
assign ferr=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_error:1'd0):legacy_fs_error;
wire [3:0] legacy_fs_dbg_state;
assign states[1]=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_dbg_state:4'd0):legacy_fs_dbg_state;
wire [7:0] legacy_fs_data;
assign bytes_data=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_data:8'd0):legacy_fs_data;
wire legacy_fs_valid;
assign fvalid=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_valid:1'd0):legacy_fs_valid;
wire legacy_fs_eof;
assign fend=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_eof:1'd0):legacy_fs_eof;
wire legacy_fs_idle_between_sectors;
assign pauseable=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_idle_between_sectors:1'd0):legacy_fs_idle_between_sectors;
wire [264:0] legacy_fs_context_out;
assign fs_context=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_context_out:265'd0):legacy_fs_context_out;
wire [31:0] legacy_fs_sd_rd_addr;
assign addr[1]=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_sd_rd_addr:32'd0):legacy_fs_sd_rd_addr;
wire [15:0] legacy_fs_sd_rd_len;
assign lens[1]=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_sd_rd_len:16'd0):legacy_fs_sd_rd_len;
wire legacy_fs_sd_rd_en;
assign en[1]=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_sd_rd_en:1'd0):legacy_fs_sd_rd_en;
wire legacy_fs_sd_data_ready;
assign dr[1]=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_sd_data_ready:1'd0):legacy_fs_sd_data_ready;
wire [31:0] legacy_fs_wk_cur_clus;
assign file_cur=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_wk_cur_clus:32'd0):legacy_fs_wk_cur_clus;
wire legacy_fs_wk_start;
assign file_ws=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_wk_start:1'd0):legacy_fs_wk_start;
wire legacy_fs_wk_rst_walk;
assign file_wr=EXTERNAL_SERVICE ? (external_service_ready ? svc_f_wk_rst_walk:1'd0):legacy_fs_wk_rst_walk;
v3_file_streamer_compact_ctx fs(.clk(clk),.rst_n(EXTERNAL_SERVICE ? 1'b0:kernel_rst_n),.context_load(load_context),.context_enable(run_kernel),
 .context_in(next_context[WP_BITS+:FS_BITS]),.context_out(legacy_fs_context_out),.stream_enable(1'b1),.idle_between_sectors(legacy_fs_idle_between_sectors),
 .start(start),.first_clus(track_clus[active]),.file_size(track_size[active]),.busy(legacy_fs_busy),.done(legacy_fs_done),.error(legacy_fs_error),.dbg_state(legacy_fs_dbg_state),
 .data(legacy_fs_data),.valid(legacy_fs_valid),.ready((parser_ready||waverr)&&run_kernel),.eof(legacy_fs_eof),
 .sec_per_clus(sec_per_clus),.fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),.total_clus(total_clus),
 .wk_cur_clus(legacy_fs_wk_cur_clus),.wk_start(legacy_fs_wk_start),.wk_rst_walk(legacy_fs_wk_rst_walk),.wk_busy(wb),.wk_done(wd),
 .wk_next_clus(w_next),.wk_eoc(w_eoc),.wk_error(we),.wk_err_code(wc),.wk_err_detail(wt),
 .sd_rd_addr(legacy_fs_sd_rd_addr),.sd_rd_len(legacy_fs_sd_rd_len),.sd_rd_en(legacy_fs_sd_rd_en),.sd_rd_ready(ready[1]),
 .sd_data(data),.sd_data_valid(dv[1]),.sd_data_ready(legacy_fs_sd_data_ready),.sd_data_last(dl[1]),.sd_rd_done(done[1]),
 .sd_timeout_err(toerr[1]),.sd_crc16_err(crcerr[1]),.sd_err_code(err_code),.sd_err_detail(err_detail));
 v3_wav_parser_compact_ctx wp(.clk(clk),.rst_n(kernel_rst_n),.context_load(load_context),.context_enable(run_kernel),
 .context_in(next_context[WP_BITS-1:0]),.context_out(wp_context),.start(start),.first_clus(track_clus[active]),
 .file_size(track_size[active]),.track_id({6'd0,active}),.din(bytes_data),.din_valid(fvalid&&!waverr&&run_kernel),
 .din_ready(parser_ready),.din_eof(fend),.sample(sample),.pcm_valid(sample_valid),
 .pcm_ready(pcm_ready[active]&&run_kernel),.wav_error(waverr));

 reg [1:0] phase,owner;reg [4:0] arm_wait;reg [1:0] pick;reg want;
 always @*begin pick=0;want=0;
  if(states[2]==1)begin pick=2;want=1;end
  else if(!index_done&&states[0]==1)begin pick=0;want=1;end
  else if(state==Q_RUN&&!pause_boundary&&states[1]==1)begin pick=1;want=1;end
 end
 assign rd_en=phase==1&&en[owner];assign rd_addr=addr[owner];assign rd_len=lens[owner];
 assign data_ready=phase==2&&dr[owner];
 genvar g;generate for(g=0;g<3;g=g+1)begin:sector_routes
  assign ready[g]=phase==1&&owner==g&&rd_ready;
  assign dv[g]=phase==2&&owner==g&&data_valid;
  assign dl[g]=phase==2&&owner==g&&data_last;
  assign done[g]=phase==2&&owner==g&&rd_done;
  assign toerr[g]=phase==2&&owner==g&&timeout_err;
  assign crcerr[g]=phase==2&&owner==g&&crc16_err;
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;owner<=0;arm_wait<=0;end
  else case(phase)
   0:if(want)begin owner<=pick;phase<=1;arm_wait<=0;end
   1:if(en[owner]&&rd_ready)phase<=2;
    else if(arm_wait==15)phase<=0;else arm_wait<=arm_wait+1'b1;
   2:if(rd_done||timeout_err||crc16_err)phase<=0;
   default:phase<=0;
  endcase
 end
assign core_cmd={kernel_rst_n,scan_start,1'b1,load_context,run_kernel,start,track_clus[active],track_size[active],(parser_ready||waverr)&&run_kernel,{129'd0,next_context[WP_BITS+:FS_BITS]},load_context,next_context[WP_BITS+FS_BITS+:32],index_done ? (run_kernel&&file_wr):scan_wr,index_done ? (run_kernel&&file_ws):scan_ws,index_done ? file_cur:scan_cur,ready,dv,dl,done,toerr,crcerr,data,err_code,err_detail};
endmodule
