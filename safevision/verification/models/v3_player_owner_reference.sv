


`include "safevision_defs.vh"
`include "pixel_format_defs.vh"

module v3_player_owner_reference #(

    parameter integer CLK_HZ      = 50_000_000,
    parameter integer SHARED_SERVICE = 0,
    parameter integer GUARDED_CS = 0,
    parameter integer RESIDENT_CACHE = 0,


    parameter [15:0]  CLK_DIV_INIT = 16'd249,
    parameter [15:0]  CLK_DIV_FAST = 16'd0,


    parameter [31:0]  INIT_TO_N    = 32'd100_000_000,
    parameter [31:0]  MOUNT_TO_N   = 32'd5_000_000,
    parameter [31:0]  STREAM_TO_N  = 32'd150_000_000,
    parameter [31:0]  SWAP_TO_N    = 32'd5_000_000,
    parameter [31:0]  PILOT_TO_N   = 32'd2_500_000,


    parameter [3:0]   INIT_RETRY_MAX = 4'd15
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cs_guard_rst_n,


    input  wire        run,
    input  wire        btn_next,
    input  wire        btn_auto,
    input  wire        restart,


    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso,


    output wire [31:0] px_word,
    output wire        px_word_valid,
    input  wire        px_word_ready,
    output reg         frame_active,
    output reg         top_down_o,
    output wire [1:0]  slot_o,


    input  wire        mem_ready,
    input  wire        frame_done,
    input  wire        last_frame_ok,


    output reg  [3:0]  state_o,
    output reg  [3:0]  fail_stage,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,


    output wire [7:0]  init_r1,
    output wire [2:0]  init_seq,
    output reg         sd_ready,
    output reg         card_usable,
    output wire [3:0]  file_cnt,
    output reg  [1:0]  cur_file,
    output reg  [31:0] cur_file_size,
    output reg  [31:0] cur_bytes_rd,
    output reg  [18:0] cur_px_written,
    output reg         last_frame_ok_o,
    output reg  [15:0] frame_cnt,
    output reg [3:0] cache_valid,
    output reg [2:0] cache_count,
    output reg [63:0] cache_keys,
    output reg [15:0] rejected_files,


    input wire[444:0] external_core_cmd,output wire[836:0] external_core_rsp,output wire external_service_ready,
    input wire ext_rd_en,input wire[31:0] ext_rd_addr,input wire[15:0] ext_rd_len,
    output wire ext_rd_ready,output wire[7:0] ext_data,output wire ext_data_valid,
    input wire ext_data_ready,output wire ext_data_last,ext_rd_done,ext_timeout,ext_crc_error,
    output wire[7:0] ext_err_code,ext_err_detail,
    output wire[7:0] fs_sec_per_clus,
    output wire[31:0] fs_fat_start_lba,fs_data_start_lba,fs_root_dir_lba,fs_root_clus,fs_total_clus,
    output reg[31:0] progress_count,
    output reg[15:0] last_reject_error,last_reject_key
);


    localparam [3:0] S_IDLE   = 4'd0,
                     S_INIT   = 4'd1,
                     S_MBR    = 4'd2,
                     S_BOOT   = 4'd3,
                     S_SCAN   = 4'd4,
                     S_INDEX  = 4'd5,
                     S_PICK   = 4'd6,
                     S_READY  = 4'd7,
                     S_STREAM = 4'd8,
                     S_SWAP   = 4'd9,
                     S_ERROR  = 4'd10,
                     S_REJECT = 4'd12,
                     S_CLEAN = 4'd13,
                     S_INITR  = 4'd11;


    localparam [7:0] MY_TO_INIT   = 8'hE1,
                     MY_TO_MOUNT  = 8'hE2,
                     MY_TO_STREAM = 8'hE3,
                     MY_TO_SWAP   = 8'hE4,
                     MY_NO_FILE   = 8'hE5;

    localparam [3:0] ST_INIT = 4'd1, ST_MBR = 4'd2, ST_BOOT = 4'd3,
                     ST_SCAN = 4'd4, ST_IDX = 4'd5, ST_PICK = 4'd6,
                     ST_STREAM = 4'd7, ST_SWAP = 4'd8;


    wire        sdhc, init_done, init_error;
    wire [7:0]  init_ec, init_ed;
    wire        init_cs_n, init_txv;
    wire [7:0]  init_txd;
    wire [15:0] init_div;
    reg         init_start;


    reg         mp_start;
    wire        mp_done, mp_has;
    wire [7:0]  mp_ec, mp_ed;
    wire [31:0] mp_vol_base, mp_part_secs;
    wire [31:0] mp_rd_addr; wire [15:0] mp_rd_len; wire mp_rd_en, mp_data_ready;


    reg         bp_start;
    wire        bp_done, bp_err;
    wire [7:0]  bp_ec, bp_ed;
    wire [15:0] bp_bps;
    wire [7:0]  bp_spc, bp_nfat;
    wire [31:0] bp_fat_lba, bp_root_clus, bp_root_lba, bp_data_lba, bp_tot_sec, bp_tot_clus;
    wire [31:0] bp_rd_addr; wire [15:0] bp_rd_len; wire bp_rd_en, bp_data_ready;


    reg         scan_en;
    wire        scan_done, dir_bad;
    wire [7:0]  dn_ec, dn_ed;
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid, ent_ready;
    wire [31:0] dn_rd_addr; wire [15:0] dn_rd_len; wire dn_rd_en, dn_data_ready;
    wire [31:0] dn_wk_cur, dn_wk_next;
    wire        dn_wk_start, dn_wk_rst, dn_wk_busy, dn_wk_done, dn_wk_eoc, dn_wk_err;
    wire [7:0]  dn_wk_ec, dn_wk_ed;
    wire [31:0] wd_rd_addr; wire [15:0] wd_rd_len; wire wd_rd_en, wd_data_ready;


    reg         idx_clear, idx_commit;
    wire        idx_done;
    wire [3:0]  file_valid;
    wire        insufficient;
    wire [7:0]  idx_ec, idx_ed;
    wire [31:0] sel_first_clus, sel_size;
    wire        sel_valid;
    wire [31:0] sel_wav_clus, sel_wav_size;
    wire        sel_wav_valid;
    wire [15:0] bmp_seen, wav_seen;


    reg         fst_start;
    wire        fst_busy, fst_done, fst_error;
    wire [7:0]  fst_ec, fst_ed;
    wire [31:0] fst_bytes;
    wire [7:0]  fst_data;
    wire        fst_valid, fst_sof, fst_eof;
    wire [31:0] fst_rd_addr; wire [15:0] fst_rd_len; wire fst_rd_en, fst_data_ready;
    wire [31:0] fst_wk_cur, fst_wk_next;
    wire        fst_wk_start, fst_wk_rst, fst_wk_busy, fst_wk_done, fst_wk_eoc, fst_wk_err;
    wire [7:0]  fst_wk_ec, fst_wk_ed;
    wire [31:0] wf_rd_addr; wire [15:0] wf_rd_len; wire wf_rd_en, wf_data_ready;


    wire        bp_ready;
    wire        bmp_check_done, bmp_check_error;
    wire [7:0]  bmp_ec, bmp_ed;
    wire [15:0] bmp_width, bmp_height;
    wire        bmp_top_down;
    wire [7:0]  bmp_bpp;
    wire [31:0] bmp_compression, bmp_pixel_off, bmp_file_size_o;
    wire [7:0]  bpo_data;
    wire        bpo_valid, bpo_sof, bpo_eof, bpo_ready;


    wire [15:0] bpu_pixel;
    wire        bpu_valid, bpu_ready;
    wire [9:0]  bpu_x, bpu_y;
    wire        bpu_sof, bpu_eof, bpu_done, bpu_error;
    wire [7:0]  bpu_ec, bpu_ed;


    reg  [15:0] lo_px;
    reg         have_lo;
    reg  [31:0] hold_word;
    reg         hold_valid;
    assign px_word       = hold_word;
    assign px_word_valid = hold_valid;


    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_to, rd_crc;
    wire [7:0]  rd_ec, rd_ed;
    wire        rd_cs_n, rd_txv;
    wire [7:0]  rd_txd;
    wire [15:0] rd_div;
    wire        spi_busy, spi_rxv, spi_tx_ready;
    wire        spi_engine_ready, spi_cs_ready;
    assign spi_tx_ready=spi_engine_ready && spi_cs_ready;
    wire [7:0]  spi_rxd;


    reg [15:0] cursor_key;
    wire [15:0] selected_key;


    wire file_rst_n = rst_n && !(RESIDENT_CACHE && state_o==S_CLEAN);
    reg  [1:0]  out_slot;
    reg  [1:0]  pick_slot;
    reg  [31:0] pick_to;

    wire [1:0]  last_slot = (file_cnt == 4'd4) ? 2'd3 : (file_cnt[1:0] - 2'd1);


    wire scan_wk = (state_o == S_SCAN)   && dn_wk_busy;
    wire strm_wk = (state_o == S_STREAM) && fst_wk_busy;
    wire ext_owner=RESIDENT_CACHE && state_o==S_READY && cache_count==4;
    assign ext_rd_ready=ext_owner && rd_ready;
    assign ext_data=rd_data;
    assign ext_data_valid=ext_owner && rd_data_valid;
    assign ext_data_last=ext_owner && rd_data_last;
    assign ext_rd_done=ext_owner && rd_done;
    assign ext_timeout=ext_owner && rd_to;
    assign ext_crc_error=ext_owner && rd_crc;
    assign ext_err_code=rd_ec,ext_err_detail=rd_ed;
    assign fs_sec_per_clus=bp_spc,fs_fat_start_lba=bp_fat_lba,fs_data_start_lba=bp_data_lba;
    assign fs_root_dir_lba=bp_root_lba,fs_root_clus=bp_root_clus,fs_total_clus=bp_tot_clus;

    wire        bus_rd_en   = (state_o == S_MBR)  ? mp_rd_en :
                              (state_o == S_BOOT) ? bp_rd_en :
                              (state_o == S_SCAN) ? (scan_wk ? wd_rd_en : dn_rd_en) :
                              (state_o == S_STREAM) ? (strm_wk ? wf_rd_en : fst_rd_en) :
                              ext_owner ? ext_rd_en : 1'b0;
    wire [31:0] bus_rd_addr = (state_o == S_MBR)  ? mp_rd_addr :
                              (state_o == S_BOOT) ? bp_rd_addr :
                              (state_o == S_SCAN) ? (scan_wk ? wd_rd_addr : dn_rd_addr) :
                              (state_o == S_STREAM) ? (strm_wk ? wf_rd_addr : fst_rd_addr) :
                              ext_owner ? ext_rd_addr : 32'd0;
    wire [15:0] bus_rd_len  = (state_o == S_MBR)  ? mp_rd_len :
                              (state_o == S_BOOT) ? bp_rd_len :
                              (state_o == S_SCAN) ? (scan_wk ? wd_rd_len : dn_rd_len) :
                              (state_o == S_STREAM) ? (strm_wk ? wf_rd_len : fst_rd_len) :
                              ext_owner ? ext_rd_len : 16'd0;
    wire        bus_data_ready = (state_o == S_MBR)  ? mp_data_ready :
                                 (state_o == S_BOOT) ? bp_data_ready :
                                 (state_o == S_SCAN) ? (scan_wk ? wd_data_ready : dn_data_ready) :
                                 (state_o == S_STREAM) ? (strm_wk ? wf_data_ready : fst_data_ready) :
                                 ext_owner ? ext_data_ready : 1'b1;


    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)progress_count<=0;
        else if(rd_data_valid && bus_data_ready)progress_count<=progress_count+1'b1;
    end


    wire [31:0] rd_addr_to_reader = bus_rd_addr + mp_vol_base;


    sd_initializer #(
        .CLK_DIV_INIT(CLK_DIV_INIT)
    ) u_init (
        .clk(clk), .rst_n(rst_n), .start(init_start),
        .sdhc(sdhc), .init_done(init_done), .init_error(init_error),
        .err_code(init_ec), .err_detail(init_ed), .retry_cnt(), .dbg_state(),
        .dbg_r1(init_r1), .dbg_seq(init_seq),
        .spi_cs_n(init_cs_n), .spi_clk_div(init_div),
        .spi_tx_valid(init_txv), .spi_tx_data(init_txd),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rxd), .spi_rx_valid(spi_rxv)
    );

    mbr_parser u_mbr (
        .clk(clk), .rst_n(rst_n), .start(mp_start),
        .parse_done(mp_done), .err_code(mp_ec), .err_detail(mp_ed), .dbg_state(),
        .has_mbr(mp_has), .vol_base_lba(mp_vol_base), .part_secs(mp_part_secs),
        .sd_rd_addr(mp_rd_addr), .sd_rd_len(mp_rd_len), .sd_rd_en(mp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(mp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_boot_parser u_boot (
        .clk(clk), .rst_n(rst_n), .start(bp_start),
        .mount_done(bp_done), .mount_error(bp_err), .err_code(bp_ec), .err_detail(bp_ed),
        .dbg_state(),
        .bytes_per_sec(bp_bps), .sec_per_clus(bp_spc), .num_fats(bp_nfat),
        .fat_start_lba(bp_fat_lba), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .total_sec(bp_tot_sec), .total_clus(bp_tot_clus),
        .sd_rd_addr(bp_rd_addr), .sd_rd_len(bp_rd_len), .sd_rd_en(bp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(bp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );


    reg service_owner_q,service_gap;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)begin service_owner_q<=0;service_gap<=0;end
      else begin service_owner_q<=ext_owner;service_gap<=(service_owner_q==ext_owner);end
    wire service_ready_int=service_gap&&(service_owner_q==ext_owner)&&rst_n;
    wire[444:0] local_core_cmd,selected_core_cmd;
    wire[836:0] physical_core_rsp;
    assign external_service_ready=SHARED_SERVICE&&ext_owner&&service_ready_int;
    assign external_core_rsp=external_service_ready?physical_core_rsp:837'd0;
    assign selected_core_cmd=ext_owner?external_core_cmd:local_core_cmd;
assign local_core_cmd={file_rst_n,scan_en,ent_ready,1'b0,1'b1,fst_start,sel_first_clus,sel_size,bp_ready,265'd0,1'b0,32'd0,state_o==S_STREAM?fst_wk_rst:dn_wk_rst,state_o==S_STREAM?fst_wk_start:dn_wk_start,state_o==S_STREAM?fst_wk_cur:dn_wk_cur,({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_ready}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_data_valid}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_data_last}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_done}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_to}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_crc}}),rd_data,rd_ec,rd_ed};
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
assign {svc_d_scan_done,svc_d_dir_bad,svc_d_err_code,svc_d_err_detail,svc_d_dbg_state,svc_d_ent_name,svc_d_ent_attr,svc_d_ent_first_clus,svc_d_ent_size,svc_d_ent_index,svc_d_ent_valid,svc_d_sd_rd_addr,svc_d_sd_rd_len,svc_d_sd_rd_en,svc_d_sd_data_ready,svc_d_wk_cur_clus,svc_d_wk_start,svc_d_wk_rst_walk,svc_f_busy,svc_f_done,svc_f_error,svc_f_err_code,svc_f_err_detail,svc_f_bytes_rd,svc_f_dbg_state,svc_f_data,svc_f_valid,svc_f_sof,svc_f_eof,svc_f_idle_between_sectors,svc_f_context_out,svc_f_sd_rd_addr,svc_f_sd_rd_len,svc_f_sd_rd_en,svc_f_sd_data_ready,svc_f_wk_cur_clus,svc_f_wk_start,svc_f_wk_rst_walk,svc_w_busy,svc_w_done,svc_w_next_clus,svc_w_eoc,svc_w_error,svc_w_err_code,svc_w_err_detail,svc_w_hop_cnt,svc_w_dbg_state,svc_w_sd_rd_addr,svc_w_sd_rd_len,svc_w_sd_rd_en,svc_w_sd_data_ready}=physical_core_rsp;
generate if(SHARED_SERVICE)begin:shared_service
      v3_shared_fs_service service(.clk(clk),.rst_n(service_ready_int),.sec_per_clus(bp_spc),
       .fat_start_lba(bp_fat_lba),.data_start_lba(bp_data_lba),.root_dir_lba(bp_root_lba),
       .root_clus(bp_root_clus),.total_clus(bp_tot_clus),.core_cmd(selected_core_cmd),.core_rsp(physical_core_rsp));
    end else begin:no_shared_service
      assign physical_core_rsp=837'd0;
    end endgenerate

wire legacy_u_scan_scan_done;
assign scan_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_scan_done:1'd0):legacy_u_scan_scan_done;
wire legacy_u_scan_dir_bad;
assign dir_bad=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_dir_bad:1'd0):legacy_u_scan_dir_bad;
wire [7:0] legacy_u_scan_err_code;
assign dn_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_err_code:8'd0):legacy_u_scan_err_code;
wire [7:0] legacy_u_scan_err_detail;
assign dn_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_err_detail:8'd0):legacy_u_scan_err_detail;
wire [87:0] legacy_u_scan_ent_name;
assign ent_name=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_name:88'd0):legacy_u_scan_ent_name;
wire [7:0] legacy_u_scan_ent_attr;
assign ent_attr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_attr:8'd0):legacy_u_scan_ent_attr;
wire [31:0] legacy_u_scan_ent_first_clus;
assign ent_first_clus=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_first_clus:32'd0):legacy_u_scan_ent_first_clus;
wire [31:0] legacy_u_scan_ent_size;
assign ent_size=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_size:32'd0):legacy_u_scan_ent_size;
wire [15:0] legacy_u_scan_ent_index;
assign ent_index=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_index:16'd0):legacy_u_scan_ent_index;
wire legacy_u_scan_ent_valid;
assign ent_valid=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_valid:1'd0):legacy_u_scan_ent_valid;
wire [31:0] legacy_u_scan_sd_rd_addr;
assign dn_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_rd_addr:32'd0):legacy_u_scan_sd_rd_addr;
wire [15:0] legacy_u_scan_sd_rd_len;
assign dn_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_rd_len:16'd0):legacy_u_scan_sd_rd_len;
wire legacy_u_scan_sd_rd_en;
assign dn_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_rd_en:1'd0):legacy_u_scan_sd_rd_en;
wire legacy_u_scan_sd_data_ready;
assign dn_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_data_ready:1'd0):legacy_u_scan_sd_data_ready;
wire [31:0] legacy_u_scan_wk_cur_clus;
assign dn_wk_cur=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_wk_cur_clus:32'd0):legacy_u_scan_wk_cur_clus;
wire legacy_u_scan_wk_start;
assign dn_wk_start=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_wk_start:1'd0):legacy_u_scan_wk_start;
wire legacy_u_scan_wk_rst_walk;
assign dn_wk_rst=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_wk_rst_walk:1'd0):legacy_u_scan_wk_rst_walk;
fat32_directory_scanner u_scan (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:rst_n), .scan_en(scan_en),
        .scan_done(legacy_u_scan_scan_done), .dir_bad(legacy_u_scan_dir_bad), .err_code(legacy_u_scan_err_code), .err_detail(legacy_u_scan_err_detail),
        .dbg_state(),
        .sec_per_clus(bp_spc), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .ent_name(legacy_u_scan_ent_name), .ent_attr(legacy_u_scan_ent_attr), .ent_first_clus(legacy_u_scan_ent_first_clus),
        .ent_size(legacy_u_scan_ent_size), .ent_index(legacy_u_scan_ent_index), .ent_valid(legacy_u_scan_ent_valid), .ent_ready(ent_ready),
        .sd_rd_addr(legacy_u_scan_sd_rd_addr), .sd_rd_len(legacy_u_scan_sd_rd_len), .sd_rd_en(legacy_u_scan_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_scan_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed),
        .wk_cur_clus(legacy_u_scan_wk_cur_clus), .wk_start(legacy_u_scan_wk_start), .wk_rst_walk(legacy_u_scan_wk_rst_walk),
        .wk_busy(dn_wk_busy), .wk_done(dn_wk_done), .wk_next_clus(dn_wk_next),
        .wk_eoc(dn_wk_eoc), .wk_error(dn_wk_err), .wk_err_code(dn_wk_ec), .wk_err_detail(dn_wk_ed)
    );

    wire legacy_u_wk_dir_busy;
assign dn_wk_busy=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_busy:1'd0):legacy_u_wk_dir_busy;
wire legacy_u_wk_dir_done;
assign dn_wk_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_done:1'd0):legacy_u_wk_dir_done;
wire [31:0] legacy_u_wk_dir_next_clus;
assign dn_wk_next=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_next_clus:32'd0):legacy_u_wk_dir_next_clus;
wire legacy_u_wk_dir_eoc;
assign dn_wk_eoc=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_eoc:1'd0):legacy_u_wk_dir_eoc;
wire legacy_u_wk_dir_error;
assign dn_wk_err=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_error:1'd0):legacy_u_wk_dir_error;
wire [7:0] legacy_u_wk_dir_err_code;
assign dn_wk_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_code:8'd0):legacy_u_wk_dir_err_code;
wire [7:0] legacy_u_wk_dir_err_detail;
assign dn_wk_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_detail:8'd0):legacy_u_wk_dir_err_detail;
wire [31:0] legacy_u_wk_dir_sd_rd_addr;
assign wd_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_addr:32'd0):legacy_u_wk_dir_sd_rd_addr;
wire [15:0] legacy_u_wk_dir_sd_rd_len;
assign wd_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_len:16'd0):legacy_u_wk_dir_sd_rd_len;
wire legacy_u_wk_dir_sd_rd_en;
assign wd_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_en:1'd0):legacy_u_wk_dir_sd_rd_en;
wire legacy_u_wk_dir_sd_data_ready;
assign wd_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_data_ready:1'd0):legacy_u_wk_dir_sd_data_ready;
fat32_cluster_walker u_wk_dir (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:rst_n), .rst_walk(dn_wk_rst), .start(dn_wk_start),
        .cur_clus(dn_wk_cur), .busy(legacy_u_wk_dir_busy), .done(legacy_u_wk_dir_done), .next_clus(legacy_u_wk_dir_next_clus),
        .eoc(legacy_u_wk_dir_eoc), .error(legacy_u_wk_dir_error), .err_code(legacy_u_wk_dir_err_code), .err_detail(legacy_u_wk_dir_err_detail),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(legacy_u_wk_dir_sd_rd_addr), .sd_rd_len(legacy_u_wk_dir_sd_rd_len), .sd_rd_en(legacy_u_wk_dir_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_wk_dir_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );


    reg  [87:0] ent_name_q;
    reg  [7:0]  ent_attr_q;
    reg  [31:0] ent_first_clus_q, ent_size_q;
    reg  [15:0] ent_index_q;
    reg         ent_valid_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ent_name_q <= 88'd0; ent_attr_q <= 8'd0; ent_first_clus_q <= 32'd0;
            ent_size_q <= 32'd0; ent_index_q <= 16'd0; ent_valid_q <= 1'b0;
        end else begin
            ent_name_q       <= ent_name;
            ent_attr_q       <= ent_attr;
            ent_first_clus_q <= ent_first_clus;
            ent_size_q       <= ent_size;
            ent_index_q      <= ent_index;
            ent_valid_q      <= ent_valid;
        end
    end

    file_index #(.CURSOR_MODE(RESIDENT_CACHE),.CANDIDATE_SLOTS(RESIDENT_CACHE?1:4)) u_idx (
        .clk(clk), .rst_n(rst_n),
        .ent_name(ent_name_q), .ent_attr(ent_attr_q), .ent_first_clus(ent_first_clus_q),
        .ent_size(ent_size_q), .ent_index(ent_index_q),
        .ent_valid(ent_valid_q), .ent_ready(ent_ready),
        .cursor_key(cursor_key), .sel_key(selected_key),
        .idx_clear(idx_clear), .idx_commit(idx_commit), .idx_done(idx_done),
        .file_cnt(file_cnt), .file_valid(file_valid), .insufficient(insufficient),
        .err_code(idx_ec), .err_detail(idx_ed),
        .sel_slot(pick_slot), .sel_first_clus(sel_first_clus), .sel_size(sel_size),
        .sel_valid(sel_valid),
        .sel_wav_first_clus(sel_wav_clus), .sel_wav_size(sel_wav_size),
        .sel_wav_valid(sel_wav_valid),
        .bmp_seen(bmp_seen), .wav_seen(wav_seen)
    );

    wire legacy_u_fst_busy;
assign fst_busy=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_busy:1'd0):legacy_u_fst_busy;
wire legacy_u_fst_done;
assign fst_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_done:1'd0):legacy_u_fst_done;
wire legacy_u_fst_error;
assign fst_error=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_error:1'd0):legacy_u_fst_error;
wire [7:0] legacy_u_fst_err_code;
assign fst_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_err_code:8'd0):legacy_u_fst_err_code;
wire [7:0] legacy_u_fst_err_detail;
assign fst_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_err_detail:8'd0):legacy_u_fst_err_detail;
wire [31:0] legacy_u_fst_bytes_rd;
assign fst_bytes=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_bytes_rd:32'd0):legacy_u_fst_bytes_rd;
wire [7:0] legacy_u_fst_data;
assign fst_data=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_data:8'd0):legacy_u_fst_data;
wire legacy_u_fst_valid;
assign fst_valid=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_valid:1'd0):legacy_u_fst_valid;
wire legacy_u_fst_sof;
assign fst_sof=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sof:1'd0):legacy_u_fst_sof;
wire legacy_u_fst_eof;
assign fst_eof=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_eof:1'd0):legacy_u_fst_eof;
wire [31:0] legacy_u_fst_sd_rd_addr;
assign fst_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_rd_addr:32'd0):legacy_u_fst_sd_rd_addr;
wire [15:0] legacy_u_fst_sd_rd_len;
assign fst_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_rd_len:16'd0):legacy_u_fst_sd_rd_len;
wire legacy_u_fst_sd_rd_en;
assign fst_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_rd_en:1'd0):legacy_u_fst_sd_rd_en;
wire legacy_u_fst_sd_data_ready;
assign fst_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_data_ready:1'd0):legacy_u_fst_sd_data_ready;
wire [31:0] legacy_u_fst_wk_cur_clus;
assign fst_wk_cur=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_wk_cur_clus:32'd0):legacy_u_fst_wk_cur_clus;
wire legacy_u_fst_wk_start;
assign fst_wk_start=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_wk_start:1'd0):legacy_u_fst_wk_start;
wire legacy_u_fst_wk_rst_walk;
assign fst_wk_rst=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_wk_rst_walk:1'd0):legacy_u_fst_wk_rst_walk;
file_streamer u_fst (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:file_rst_n),
        .start(fst_start), .first_clus(sel_first_clus), .file_size(sel_size),
        .busy(legacy_u_fst_busy), .done(legacy_u_fst_done), .error(legacy_u_fst_error),
        .err_code(legacy_u_fst_err_code), .err_detail(legacy_u_fst_err_detail),
        .bytes_rd(legacy_u_fst_bytes_rd), .dbg_state(),
        .data(legacy_u_fst_data), .valid(legacy_u_fst_valid), .ready(bp_ready), .sof(legacy_u_fst_sof), .eof(legacy_u_fst_eof),
        .sec_per_clus(bp_spc), .fat_start_lba(bp_fat_lba),
        .data_start_lba(bp_data_lba), .total_clus(bp_tot_clus),
        .wk_cur_clus(legacy_u_fst_wk_cur_clus), .wk_start(legacy_u_fst_wk_start), .wk_rst_walk(legacy_u_fst_wk_rst_walk),
        .wk_busy(fst_wk_busy), .wk_done(fst_wk_done), .wk_next_clus(fst_wk_next),
        .wk_eoc(fst_wk_eoc), .wk_error(fst_wk_err),
        .wk_err_code(fst_wk_ec), .wk_err_detail(fst_wk_ed),
        .sd_rd_addr(legacy_u_fst_sd_rd_addr), .sd_rd_len(legacy_u_fst_sd_rd_len), .sd_rd_en(legacy_u_fst_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_fst_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    wire legacy_u_wk_fst_busy;
assign fst_wk_busy=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_busy:1'd0):legacy_u_wk_fst_busy;
wire legacy_u_wk_fst_done;
assign fst_wk_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_done:1'd0):legacy_u_wk_fst_done;
wire [31:0] legacy_u_wk_fst_next_clus;
assign fst_wk_next=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_next_clus:32'd0):legacy_u_wk_fst_next_clus;
wire legacy_u_wk_fst_eoc;
assign fst_wk_eoc=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_eoc:1'd0):legacy_u_wk_fst_eoc;
wire legacy_u_wk_fst_error;
assign fst_wk_err=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_error:1'd0):legacy_u_wk_fst_error;
wire [7:0] legacy_u_wk_fst_err_code;
assign fst_wk_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_code:8'd0):legacy_u_wk_fst_err_code;
wire [7:0] legacy_u_wk_fst_err_detail;
assign fst_wk_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_detail:8'd0):legacy_u_wk_fst_err_detail;
wire [31:0] legacy_u_wk_fst_sd_rd_addr;
assign wf_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_addr:32'd0):legacy_u_wk_fst_sd_rd_addr;
wire [15:0] legacy_u_wk_fst_sd_rd_len;
assign wf_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_len:16'd0):legacy_u_wk_fst_sd_rd_len;
wire legacy_u_wk_fst_sd_rd_en;
assign wf_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_en:1'd0):legacy_u_wk_fst_sd_rd_en;
wire legacy_u_wk_fst_sd_data_ready;
assign wf_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_data_ready:1'd0):legacy_u_wk_fst_sd_data_ready;
fat32_cluster_walker u_wk_fst (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:file_rst_n), .rst_walk(fst_wk_rst), .start(fst_wk_start),
        .cur_clus(fst_wk_cur), .busy(legacy_u_wk_fst_busy), .done(legacy_u_wk_fst_done), .next_clus(legacy_u_wk_fst_next_clus),
        .eoc(legacy_u_wk_fst_eoc), .error(legacy_u_wk_fst_error), .err_code(legacy_u_wk_fst_err_code), .err_detail(legacy_u_wk_fst_err_detail),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(legacy_u_wk_fst_sd_rd_addr), .sd_rd_len(legacy_u_wk_fst_sd_rd_len), .sd_rd_en(legacy_u_wk_fst_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_wk_fst_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );


    bmp_parser u_bmp (
        .clk(clk), .rst_n(file_rst_n),
        .data(fst_data), .valid(fst_valid), .ready(bp_ready), .eof(fst_eof),
        .file_size(sel_size),
        .check_done(bmp_check_done), .check_error(bmp_check_error),
        .err_code(bmp_ec), .err_detail(bmp_ed),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_top_down),
        .bpp(bmp_bpp), .compression(bmp_compression), .pixel_off(bmp_pixel_off),
        .file_size_o(bmp_file_size_o), .dbg_state(),
        .out_data(bpo_data), .out_valid(bpo_valid), .out_ready(bpo_ready),
        .out_sof(bpo_sof), .out_eof(bpo_eof)
    );


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lo_px <= 16'd0; have_lo <= 1'b0; hold_word <= 32'd0; hold_valid <= 1'b0;
        end else if (RESIDENT_CACHE && state_o==S_CLEAN) begin
            lo_px<=0;have_lo<=0;hold_word<=0;hold_valid<=0;
        end else begin
            if (hold_valid && px_word_ready) hold_valid <= 1'b0;
            if (bpu_valid && bpu_ready) begin
                if (!have_lo) begin
                    lo_px   <= bpu_pixel;
                    have_lo <= 1'b1;
                end else begin
                    hold_word  <= {bpu_pixel, lo_px};
                    hold_valid <= 1'b1;
                    have_lo    <= 1'b0;
                end
            end
        end
    end

    assign bpu_ready = !hold_valid || px_word_ready;

    bmp_unpack u_unpack (
        .clk(clk), .rst_n(file_rst_n),
        .din(bpo_data), .din_valid(bpo_valid), .din_ready(bpo_ready),
        .din_sof(bpo_sof), .din_eof(bpo_eof),


        .width(RESIDENT_CACHE ? 16'd640 : bmp_width),
        .height(RESIDENT_CACHE ? (bmp_top_down ? -16'sd480 : 16'd480) : bmp_height),
        .top_down(bmp_top_down),
        .pixel_off(bmp_pixel_off),
        .pixel(bpu_pixel), .pixel_valid(bpu_valid), .pixel_ready(bpu_ready),
        .x(bpu_x), .y(bpu_y), .img_sof(bpu_sof), .img_eof(bpu_eof),
        .done(bpu_done), .error(bpu_error), .err_code(bpu_ec), .err_detail(bpu_ed),
        .dbg_state()
    );

    assign slot_o = out_slot;

    generate if(RESIDENT_CACHE)begin:checked_reader
    sd_checked_sector_reader #(
        .CLK_DIV_FAST(CLK_DIV_FAST)
    ) u_rd (
        .clk(clk), .rst_n(file_rst_n), .sdhc(sdhc),
        .rd_en(bus_rd_en), .rd_addr(rd_addr_to_reader), .rd_len(bus_rd_len),
        .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(bus_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to), .crc16_err(rd_crc),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_div),
        .spi_tx_valid(rd_txv), .spi_tx_data(rd_txd),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rxd), .spi_rx_valid(spi_rxv)
    );

    end else begin:legacy_reader
    sd_sector_reader #(
        .CLK_DIV_FAST(CLK_DIV_FAST)
    ) u_rd (
        .clk(clk), .rst_n(file_rst_n), .sdhc(sdhc),
        .rd_en(bus_rd_en), .rd_addr(rd_addr_to_reader), .rd_len(bus_rd_len),
        .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(bus_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to), .crc16_err(rd_crc),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_div),
        .spi_tx_valid(rd_txv), .spi_tx_data(rd_txd),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rxd), .spi_rx_valid(spi_rxv)
    );

    end endgenerate


    wire        spi_use_reader = sd_ready;
    wire        spi_txv  = spi_use_reader ? rd_txv  : init_txv;
    wire [7:0]  spi_txd  = spi_use_reader ? rd_txd  : init_txd;
    wire [15:0] spi_div  = spi_use_reader ? rd_div  : init_div;
    wire raw_cs_n=init_cs_n & rd_cs_n;
    generate if(GUARDED_CS)begin:guarded_cs
      v3_spi_cs_guard guard(.ref_clk(clk),.ref_rst_n(cs_guard_rst_n),
        .raw_cs_n(raw_cs_n),.raw_sclk(sd_dclk),.cs_n(sd_ncs),.cs_ready(spi_cs_ready));
    end else begin:direct_cs
      assign sd_ncs=raw_cs_n;assign spi_cs_ready=1'b1;
    end endgenerate

    spi_master #(
        .CLK_FREQ(CLK_HZ)
    ) u_spi (
        .clk(clk), .rst_n(rst_n), .clk_div(spi_div), .cs_n(raw_cs_n),
        .tx_valid(spi_txv && spi_cs_ready), .tx_data(spi_txd), .tx_ready(spi_engine_ready),
        .rx_data(spi_rxd), .rx_valid(spi_rxv), .busy(spi_busy),
        .sclk(sd_dclk), .mosi(sd_mosi), .miso(sd_miso)
    );


    reg [3:0]  state_d;
    reg [31:0] to_cnt;
    reg [1:0]  scan_sub;
    reg        stream_kicked;
    reg [3:0]  init_try;
    reg [2:0]  init_arm;
    reg        fd_d, fd_pending;
    reg fst_done_d,file_done_seen;


    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin fst_done_d<=0;file_done_seen<=0;end
        else begin
            fst_done_d<=fst_done;
            if(state_o!=S_STREAM || !stream_kicked)file_done_seen<=0;
            else if(fst_done && !fst_done_d)file_done_seen<=1;
        end
    end

    wire state_new = (state_o != state_d);


    reg [1:0] mr_sync;
    reg [1:0] fd_sync;
    reg [1:0] lok_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin mr_sync <= 2'd0; fd_sync <= 2'd0; lok_sync <= 2'd0; end
        else begin
            mr_sync  <= {mr_sync[0],  mem_ready};
            fd_sync  <= {fd_sync[0],  frame_done};
            lok_sync <= {lok_sync[0], last_frame_ok};
        end
    end
    wire mem_ready_s = mr_sync[1];


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin fd_d <= 1'b0; fd_pending <= 1'b0; end
        else begin
            fd_d <= fd_sync[1];
            if (state_o == S_STREAM && stream_kicked) begin
                if (fd_sync[1] != fd_d) fd_pending <= 1'b1;
            end else begin
                fd_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_d        <= S_IDLE;
            state_o        <= S_IDLE;
            fail_stage     <= 4'd0;
            err_code       <= 8'h00;
            err_detail     <= 8'h00;
            sd_ready       <= 1'b0;
            card_usable    <= 1'b0;
            init_start     <= 1'b0;
            mp_start       <= 1'b0;
            bp_start       <= 1'b0;
            scan_en        <= 1'b0;
            idx_clear      <= 1'b0;
            idx_commit     <= 1'b0;
            fst_start      <= 1'b0;
            to_cnt         <= 32'd0;
            scan_sub       <= 2'd0;
            stream_kicked  <= 1'b0;
            init_try       <= 4'd0;
            init_arm       <= 3'd0;
            pick_slot      <= 2'd0;
            pick_to        <= 32'd0;
            cur_file       <= 2'd0;
            cur_file_size  <= 32'd0;
            cur_bytes_rd   <= 32'd0;
            cur_px_written <= 19'd0;
            last_frame_ok_o <= 1'b0;
            frame_cnt      <= 16'd0;
            cursor_key<=0;cache_valid<=0;cache_count<=0;cache_keys<=0;rejected_files<=0;
            last_reject_error<=0;last_reject_key<=0;
            out_slot       <= RESIDENT_CACHE ? 2'd0 : 2'd1;
            frame_active   <= 1'b0;
            top_down_o     <= 1'b0;


        end else begin

            init_start <= 1'b0;
            mp_start   <= 1'b0;
            bp_start   <= 1'b0;
            scan_en    <= 1'b0;
            idx_clear  <= 1'b0;
            idx_commit <= 1'b0;
            fst_start  <= 1'b0;

            state_d <= state_o;


            cur_bytes_rd   <= fst_bytes;
            cur_px_written <= bpu_x;

            case (state_o)

                S_IDLE: begin
                    sd_ready    <= 1'b0;
                    card_usable <= 1'b0;
                    to_cnt      <= 32'd0;
                    init_try    <= 4'd0;
                    if (run) state_o <= S_INIT;
                end


                S_INIT: begin
                    if (state_new) begin init_start <= 1'b1; init_arm <= 3'd0; end
                    else if (init_arm != 3'd7) init_arm <= init_arm + 3'd1;
                    to_cnt <= to_cnt + 32'd1;
                    if (init_arm >= 3'd4) begin
                        if (init_done) begin
                            sd_ready <= 1'b1;
                            to_cnt   <= 32'd0;
                            init_try <= 4'd0;
                            state_o  <= S_MBR;
                        end else if (init_error) begin
                            if (init_try < INIT_RETRY_MAX) begin
                                init_try <= init_try + 4'd1;
                                state_o  <= S_INITR;
                            end else begin
                                fail_stage <= ST_INIT;
                                err_code   <= init_ec;
                                err_detail <= init_ed;
                                state_o    <= S_ERROR;
                            end
                        end else if (to_cnt >= INIT_TO_N) begin
                            fail_stage <= ST_INIT;
                            err_code   <= MY_TO_INIT;
                            state_o    <= S_ERROR;
                        end
                    end
                end


                S_INITR: begin
                    init_arm <= 3'd0;
                    state_o  <= S_INIT;
                end


                S_MBR: begin
                    if (state_new) mp_start <= 1'b1;
                    to_cnt <= to_cnt + 32'd1;

                    if (mp_done) begin
                        if (mp_ec != 8'h00) begin
                            fail_stage <= ST_MBR;
                            err_code   <= mp_ec;
                            err_detail <= mp_ed;
                            state_o    <= S_ERROR;
                        end else begin
                            to_cnt  <= 32'd0;
                            state_o <= S_BOOT;
                        end
                    end else if (to_cnt >= MOUNT_TO_N) begin
                        fail_stage <= ST_MBR;
                        err_code   <= MY_TO_MOUNT;
                        state_o    <= S_ERROR;
                    end
                end


                S_BOOT: begin
                    if (state_new) bp_start <= 1'b1;
                    to_cnt <= to_cnt + 32'd1;
                    if (bp_done) begin
                        if (bp_err) begin
                            fail_stage <= ST_BOOT;
                            err_code   <= bp_ec;
                            err_detail <= bp_ed;
                            state_o    <= S_ERROR;
                        end else begin
                            to_cnt   <= 32'd0;
                            scan_sub <= 2'd0;
                            state_o  <= S_SCAN;
                        end
                    end else if (to_cnt >= MOUNT_TO_N) begin
                        fail_stage <= ST_BOOT;
                        err_code   <= MY_TO_MOUNT;
                        state_o    <= S_ERROR;
                    end
                end


                S_SCAN: begin
                    to_cnt <= to_cnt + 32'd1;
                    case (scan_sub)
                        2'd0: begin idx_clear <= 1'b1; scan_sub <= 2'd1; end
                        2'd1: begin scan_en   <= 1'b1; scan_sub <= 2'd2; end
                        2'd2: begin scan_sub<=2'd3; end
                        default: begin
                            if (scan_done) begin
                                if (dir_bad) begin
                                    fail_stage <= ST_SCAN;
                                    err_code   <= dn_ec;
                                    err_detail <= dn_ed;
                                    state_o    <= S_ERROR;
                                end else begin
                                    idx_commit <= 1'b1;
                                    to_cnt     <= 32'd0;
                                    state_o    <= S_INDEX;
                                end
                            end else if (to_cnt >= MOUNT_TO_N) begin
                                fail_stage <= ST_SCAN;
                                err_code   <= MY_TO_MOUNT;
                                state_o    <= S_ERROR;
                            end
                        end
                    endcase
                end


                S_INDEX: begin
                    to_cnt <= to_cnt + 32'd1;
                    if (idx_done) begin
                        to_cnt <= 32'd0;
                        if (file_cnt == 4'd0) begin
                            fail_stage <= ST_IDX;
                            err_code   <= MY_NO_FILE;
                            state_o    <= S_ERROR;
                        end else begin
                            card_usable <= !RESIDENT_CACHE;
                            cur_file    <= 2'd0;
                            pick_slot   <= 2'd0;
                            state_o     <= S_READY;
                        end
                    end else if (to_cnt >= MOUNT_TO_N) begin
                        fail_stage <= ST_IDX;
                        err_code   <= MY_TO_MOUNT;
                        state_o    <= S_ERROR;
                    end
                end


                S_PICK: begin
                    pick_slot <= cur_file;
                    pick_to   <= pick_to + 32'd1;
                    if (pick_to >= 32'd3) begin
                        pick_to <= 32'd0;
                        if (!sel_valid) begin
                            fail_stage <= ST_PICK;
                            err_code   <= MY_NO_FILE;
                            state_o    <= S_ERROR;
                        end else begin
                            cur_file_size <= sel_size;
                            state_o       <= S_STREAM;
                        end
                    end
                end


                S_READY: begin
                    to_cnt <= 32'd0;
                    if (RESIDENT_CACHE) begin
                        if(cache_count<4) begin pick_to<=0;state_o<=S_PICK;end
                    end else if (frame_cnt == 16'd0) begin

                        cur_file  <= 2'd0;
                        pick_slot <= 2'd0;
                        pick_to   <= 32'd0;
                        state_o   <= S_PICK;
                    end else if (btn_next || btn_auto) begin

                        cur_file  <= (cur_file == last_slot) ? 2'd0 : (cur_file + 2'd1);
                        pick_slot <= (cur_file == last_slot) ? 2'd0 : (cur_file + 2'd1);
                        pick_to   <= 32'd0;
                        state_o   <= S_PICK;
                    end
                end


                S_STREAM: begin
                    to_cnt <= to_cnt + 32'd1;


                    if (!stream_kicked && mem_ready_s && !fst_busy && rd_ready) begin
                        fst_start     <= 1'b1;
                        frame_active  <= 1'b1;
                        stream_kicked <= 1'b1;
                    end


                    if (stream_kicked && bmp_check_done) top_down_o <= bmp_top_down;
                    cur_file_size <= sel_size;


                    if (stream_kicked && fd_pending && file_done_seen && !fst_error && rd_ready && !spi_busy && !rd_crc && !rd_to) begin
                        frame_active  <= 1'b0;
                        last_frame_ok_o <= lok_sync[1];
                        stream_kicked <= 1'b0;
                        to_cnt        <= 32'd0;
                        if (lok_sync[1]) begin
                            frame_cnt <= frame_cnt + 16'd1;
                            if(RESIDENT_CACHE) begin
                                cache_valid[out_slot]<=1;cache_count<=cache_count+1'b1;
                                cache_keys[out_slot*16+:16]<=selected_key;
                                if(cache_count==3)card_usable<=1;
                            end
                            state_o <= S_SWAP;
                        end else begin


                            fail_stage <= ST_STREAM;
                            err_code <= 8'hE3;
                            err_detail <= 8'h01;
                            state_o <= S_ERROR;
                        end
                    end else if (fst_error || bpu_error || bmp_check_error || (stream_kicked && (rd_crc || rd_to))) begin
                        stream_kicked <= 1'b0;
                        frame_active  <= 1'b0;
                        fail_stage    <= ST_STREAM;
                        err_code      <= (rd_crc || rd_to) ? rd_ec : fst_error ? fst_ec : (bpu_error ? bpu_ec : bmp_ec);
                        err_detail    <= (rd_crc || rd_to) ? rd_ed : fst_error ? fst_ed : (bpu_error ? bpu_ed : bmp_ed);
                        state_o       <= RESIDENT_CACHE ? S_REJECT : S_ERROR;
                        if(RESIDENT_CACHE)to_cnt<=0;
                    end else if (to_cnt >= STREAM_TO_N) begin
                        stream_kicked <= 1'b0;
                        frame_active  <= 1'b0;
                        fail_stage    <= ST_STREAM;
                        err_code      <= MY_TO_STREAM;
                        state_o       <= S_ERROR;
                    end
                end


                S_SWAP: begin
                    to_cnt <= 0;
                    if(RESIDENT_CACHE) begin


                        out_slot<=cache_count[1:0];cursor_key<=selected_key;
                        if(cache_count==4) begin state_o<=S_READY;fail_stage<=0;err_code<=0;err_detail<=0;end
                        else if(cur_file==last_slot) begin
                            cur_file<=0;pick_slot<=0;scan_sub<=0;state_o<=S_SCAN;
                        end else begin cur_file<=cur_file+1'b1;pick_slot<=cur_file+1'b1;state_o<=S_READY;end
                    end else begin out_slot<=out_slot^2'b01;state_o<=S_READY;end
                end


                S_REJECT: begin


                    frame_active<=0;to_cnt<=to_cnt+1'b1;
                    if(rd_ready && !spi_busy)begin state_o<=S_CLEAN;to_cnt<=0;end
                    else if(to_cnt>=STREAM_TO_N)begin err_code<=MY_TO_STREAM;state_o<=S_ERROR;end
                end
                S_CLEAN: begin
                    to_cnt<=to_cnt+1'b1;
                    if(to_cnt==3)begin
                        rejected_files<=rejected_files+1'b1;cursor_key<=selected_key;
                        last_reject_error<={err_code,err_detail};last_reject_key<=selected_key;
                        to_cnt<=0;stream_kicked<=0;
                        if(cur_file==last_slot)begin
                            cur_file<=0;pick_slot<=0;scan_sub<=0;state_o<=S_SCAN;
                        end else begin cur_file<=cur_file+1'b1;pick_slot<=cur_file+1'b1;state_o<=S_READY;end
                    end
                end
                S_ERROR: begin
                    sd_ready    <= 1'b0;
                    card_usable <= 1'b0;
                    if (restart) begin
                        to_cnt     <= 32'd0;
                        init_try   <= 4'd0;
                        init_arm   <= 3'd0;
                        fail_stage <= 4'd0;
                        err_code   <= 8'h00;
                        err_detail <= 8'h00;
                        frame_cnt  <= 16'd0;
                        cursor_key<=0;cache_valid<=0;cache_count<=0;cache_keys<=0;rejected_files<=0;
                        last_reject_error<=0;last_reject_key<=0;
                        out_slot<=RESIDENT_CACHE?0:1;
                        cur_file   <= 2'd0;
                        pick_slot  <= 2'd0;
                        state_o    <= S_INIT;
                    end
                end

                default: state_o <= S_IDLE;
            endcase
        end
    end

endmodule
