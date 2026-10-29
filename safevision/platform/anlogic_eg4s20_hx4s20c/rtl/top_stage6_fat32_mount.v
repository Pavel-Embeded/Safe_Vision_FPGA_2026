


`include "safevision_defs.vh"

module top_stage6_fat32_mount #(
    parameter integer CLK_FREQ    = 50_000_000,
    parameter integer BAUD        = 115200,
    parameter [23:0]  POWERUP_CYC = 24'd2_500_000,


    parameter [15:0]  RPT_N       = 16'd100
)(

    input  wire        clk,
    input  wire        rst_n,
    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        uart_txd,
    output wire [3:0]  led
);


    `ifdef SIM_FAST_TO
    localparam [31:0] TOP_TO = 32'd2_000_000;
    `else
    localparam [31:0] TOP_TO = 32'd300_000_000;
    `endif


    function [7:0] hexd;
        input [3:0] n;
        begin
            hexd = (n <= 4'd9) ? (8'h30 + {4'b0, n}) : (8'h37 + {4'b0, n});
        end
    endfunction


    function [63:0] h8;
        input [31:0] v;
        begin
            h8 = { hexd(v[31:28]), hexd(v[27:24]), hexd(v[23:20]), hexd(v[19:16]),
                   hexd(v[15:12]), hexd(v[11:8]),  hexd(v[7:4]),   hexd(v[3:0]) };
        end
    endfunction


    function [31:0] h4;
        input [31:0] v;
        begin
            h4 = { hexd(v[15:12]), hexd(v[11:8]), hexd(v[7:4]), hexd(v[3:0]) };
        end
    endfunction


    function [15:0] h2;
        input [31:0] v;
        begin
            h2 = { hexd(v[7:4]), hexd(v[3:0]) };
        end
    endfunction


    function [175:0] h11x;
        input [87:0] nm;
        begin
            h11x = {
                hexd(nm[87:84]), hexd(nm[83:80]), hexd(nm[79:76]), hexd(nm[75:72]),
                hexd(nm[71:68]), hexd(nm[67:64]), hexd(nm[63:60]), hexd(nm[59:56]),
                hexd(nm[55:52]), hexd(nm[51:48]), hexd(nm[47:44]), hexd(nm[43:40]),
                hexd(nm[39:36]), hexd(nm[35:32]), hexd(nm[31:28]), hexd(nm[27:24]),
                hexd(nm[23:20]), hexd(nm[19:16]), hexd(nm[15:12]), hexd(nm[11:8]),
                hexd(nm[7:4]),   hexd(nm[3:0])
            };
        end
    endfunction


    wire rst_sync_n;
    reset_sync u_reset_sync (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_sync_n)
    );


    localparam [3:0] ST_POWER  = 4'd0,
                     ST_INIT   = 4'd1,
                     ST_WINIT  = 4'd2,
                     ST_MBR    = 4'd3,
                     ST_WMBR   = 4'd4,
                     ST_MOUNT  = 4'd5,
                     ST_WMNT   = 4'd6,
                     ST_SCAN   = 4'd7,
                     ST_WSCAN  = 4'd8,
                     ST_REPORT = 4'd9,
                     ST_OK     = 4'd10,
                     ST_ERR    = 4'd11,
                     ST_RPT    = 4'd12,
                     ST_RPTREQ = 4'd13,
                     ST_RPTWAIT= 4'd14;

    reg  [3:0]  st;
    reg  [23:0] pwr_cnt;


    reg  [31:0] to_winit, to_wmbr, to_wmnt, to_wscan, to_rep;


    reg  [7:0]  top_err;
    reg         rep_err;


    reg  [15:0] rep_ok;
    reg  [15:0] rep_bad;
    reg  [15:0] rep_idx;


    localparam [2:0] R_IDLE = 3'd0,
                     R_HDR  = 3'd1,
                     R_ENT  = 3'd2,
                     R_RPT  = 3'd3,
                     R_ERR  = 3'd4,
                     R_DONE = 3'd5,
                     R_FIN  = 3'd6;

    reg  [2:0]  rstate;
    reg  [7:0]  pc;


    localparam integer HDR_BYTES  = 183;
    localparam integer ENT_BYTES  = 52;
    localparam integer RPT_BYTES  = 27;
    localparam integer ERR_BYTES  = 8;
    localparam integer DONE_BYTES = 6;


    localparam integer MAX_ENT = 8;
    reg  [87:0] en_name [0:MAX_ENT-1];
    reg  [7:0]  en_attr [0:MAX_ENT-1];
    reg  [31:0] en_clus [0:MAX_ENT-1];
    reg  [31:0] en_size [0:MAX_ENT-1];
    reg  [15:0] en_idx  [0:MAX_ENT-1];
    reg  [15:0] ent_total;
    reg  [2:0]  ent_cur;


    wire        sdhc;
    wire        init_done, init_error;
    wire [7:0]  init_err_code;
    wire        init_cs_n;
    wire [15:0] init_clk_div;
    wire        init_tx_valid;
    wire [7:0]  init_tx_data;


    wire        mbr_parse_done;
    wire [7:0]  mbr_err_code, mbr_err_detail;
    wire        mbr_has;
    wire [31:0] mbr_vol_base;
    wire [31:0] mbr_part_secs;
    wire [31:0] mbr_sd_rd_addr;
    wire [15:0] mbr_sd_rd_len;
    wire        mbr_sd_rd_en;
    wire        mbr_sd_data_ready;


    wire        fs_mount_done, fs_mount_error;
    wire [7:0]  fs_err_code, fs_err_detail;
    wire [15:0] fs_bps;
    wire [7:0]  fs_spc, fs_nfat;
    wire [31:0] fs_fat_lba, fs_root_clus, fs_root_lba, fs_data_lba;
    wire [31:0] fs_tot_sec, fs_tot_clus;
    wire [31:0] fs_sd_rd_addr;
    wire [15:0] fs_sd_rd_len;
    wire        fs_sd_rd_en;
    wire        fs_sd_data_ready;


    wire        scan_done, dir_bad;
    wire [7:0]  dir_err_code, dir_err_detail;
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid;
    wire [31:0] dn_sd_rd_addr;
    wire [15:0] dn_sd_rd_len;
    wire        dn_sd_rd_en;
    wire        dn_sd_data_ready;
    wire [31:0] wk_cur_clus, wk_next_clus;
    wire        wk_start, wk_rst_walk, wk_busy, wk_done, wk_eoc, wk_error;
    wire [7:0]  wk_err_code, wk_err_detail;


    wire [31:0] wk_sd_rd_addr;
    wire [15:0] wk_sd_rd_len;
    wire        wk_sd_rd_en;
    wire        wk_sd_data_ready;


    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_timeout, rd_crc16_err;
    wire [7:0]  rd_err_code, rd_err_detail;
    wire        rd_cs_n;
    wire [15:0] rd_clk_div;
    wire        rd_tx_valid;
    wire [7:0]  rd_tx_data;


    wire        spi_tx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;


    wire        uart_ready;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;


    wire init_start = (st == ST_INIT);
    wire mbr_start  = (st == ST_MBR);
    wire boot_start = (st == ST_MOUNT);
    wire scan_en    = (st == ST_SCAN);


    wire sel_mbr  = (st == ST_WMBR);
    wire sel_boot = (st == ST_WMNT);
    wire sel_scan = (st == ST_WSCAN);
    wire use_wk   = sel_scan & wk_busy;

    wire sel_rep  = (st == ST_RPTREQ) | (st == ST_RPTWAIT);


    wire        rpt_rd_en   = (st == ST_RPTREQ) && rd_ready;
    wire [31:0] rpt_rd_addr = fs_root_lba;
    wire [15:0] rpt_rd_len  = 16'd1;

    wire        bus_rd_en   = sel_rep  ? rpt_rd_en   :
                              sel_mbr  ? mbr_sd_rd_en  :
                              sel_boot ? fs_sd_rd_en   :
                              use_wk   ? wk_sd_rd_en   : dn_sd_rd_en;
    wire [31:0] bus_rd_addr = sel_rep  ? rpt_rd_addr :
                              sel_mbr  ? mbr_sd_rd_addr:
                              sel_boot ? fs_sd_rd_addr :
                              use_wk   ? wk_sd_rd_addr : dn_sd_rd_addr;
    wire [15:0] bus_rd_len  = sel_rep  ? rpt_rd_len  :
                              sel_mbr  ? mbr_sd_rd_len :
                              sel_boot ? fs_sd_rd_len  :
                              use_wk   ? wk_sd_rd_len  : dn_sd_rd_len;


    wire        bus_data_ready = sel_rep  ? 1'b1 :
                                 sel_mbr  ? mbr_sd_data_ready :
                                 sel_boot ? fs_sd_data_ready :
                                 use_wk   ? wk_sd_data_ready : dn_sd_data_ready;


    wire [31:0] rd_addr_to_reader = bus_rd_addr + mbr_vol_base;


    wire [31:0] rv_mbr     = {31'b0, mbr_has};
    wire [31:0] rv_base    = mbr_vol_base;
    wire [31:0] rv_secs    = mbr_part_secs;
    wire [31:0] rv_bps     = {16'b0, fs_bps};
    wire [31:0] rv_spc     = {24'b0, fs_spc};
    wire [31:0] rv_nfat    = {24'b0, fs_nfat};
    wire [31:0] rv_fat     = fs_fat_lba;
    wire [31:0] rv_data    = fs_data_lba;
    wire [31:0] rv_root    = fs_root_lba;
    wire [31:0] rv_totsec  = fs_tot_sec;
    wire [31:0] rv_totclus = fs_tot_clus;
    wire [31:0] rv_entcnt  = {16'b0, ent_total};
    wire [31:0] rv_err     = {24'b0, top_err};


    wire [87:0] cur_name = en_name[ent_cur];
    wire [31:0] cur_clus = en_clus[ent_cur];
    wire [31:0] cur_size = en_size[ent_cur];
    wire [7:0]  cur_attr = en_attr[ent_cur];
    wire [15:0] cur_idx  = en_idx [ent_cur];
    wire [31:0] rv_idx   = {16'b0, cur_idx};
    wire [31:0] rv_attr  = {24'b0, cur_attr};


    wire [3:0]  ent_show = (ent_total > 16'd8) ? 4'd8 : ent_total[3:0];


    wire [31:0] rv_rtot = {16'b0, RPT_N};
    wire [31:0] rv_rok  = {16'b0, rep_ok};
    wire [31:0] rv_rbad = {16'b0, rep_bad};


    wire [1463:0] hdr_bits = {
        "SAFEVISION B STAGE6", 8'h0D, 8'h0A,
        "MBR=", h8(rv_mbr), " BASE=", h8(rv_base), " SECS=", h8(rv_secs), 8'h0D, 8'h0A,
        "BPS=", h4(rv_bps), " SPC=", h2(rv_spc), " NFAT=", h2(rv_nfat), 8'h0D, 8'h0A,
        "FATLBA=", h8(rv_fat), " DATALBA=", h8(rv_data), " ROOTLBA=", h8(rv_root), 8'h0D, 8'h0A,
        "TOTSEC=", h8(rv_totsec), " TOTCLUS=", h8(rv_totclus), 8'h0D, 8'h0A,
        "ENT=", h4(rv_entcnt), 8'h0D, 8'h0A
    };


    wire [415:0] ent_bits = {
        "E ", h4(rv_idx), " ", h11x(cur_name), " ",
        h2(rv_attr), " ", h8(cur_clus), " ", h8(cur_size), 8'h0D, 8'h0A
    };


    wire [215:0] rpt_bits = {
        "RPT=", h4(rv_rtot), " OK=", h4(rv_rok), " BAD=", h4(rv_rbad), 8'h0D, 8'h0A
    };


    wire [63:0] err_bits = { "ERR=", h2(rv_err), 8'h0D, 8'h0A };


    wire [47:0] done_bits = { "DONE", 8'h0D, 8'h0A };


    reg [7:0] rp_byte;
    always @(*) begin
        case (rstate)
            R_HDR : rp_byte = hdr_bits [(1463 - 8*pc) -: 8];
            R_ENT : rp_byte = ent_bits [(415  - 8*pc) -: 8];
            R_RPT : rp_byte = rpt_bits [(215  - 8*pc) -: 8];
            R_ERR : rp_byte = err_bits [(63   - 8*pc) -: 8];
            R_DONE: rp_byte = done_bits[(47   - 8*pc) -: 8];
            default: rp_byte = 8'h00;
        endcase
    end

    wire rep_shifting = (st == ST_REPORT) &&
                        ((rstate == R_HDR) || (rstate == R_ENT) ||
                         (rstate == R_RPT) || (rstate == R_ERR) ||
                         (rstate == R_DONE));
    assign uart_tx_valid = rep_shifting & uart_ready;
    assign uart_tx_data  = rp_byte;


    wire spi_use_reader = init_done;
    wire        spi_tx_valid = spi_use_reader ? rd_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_use_reader ? rd_tx_data  : init_tx_data;
    wire [15:0] spi_clk_div  = spi_use_reader ? rd_clk_div  : init_clk_div;
    assign sd_ncs = init_cs_n & rd_cs_n;


    wire ent_ready = 1'b1;

    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            st        <= ST_POWER;
            pwr_cnt   <= 24'd0;
            to_winit  <= 32'd0;
            to_wmbr   <= 32'd0;
            to_wmnt   <= 32'd0;
            to_wscan  <= 32'd0;
            to_rep    <= 32'd0;
            top_err   <= `ERR_NONE;
            rep_err   <= 1'b0;
            rstate    <= R_IDLE;
            pc        <= 8'd0;
            ent_cur   <= 3'd0;
            ent_total <= 16'd0;
            rep_ok    <= 16'd0;
            rep_bad   <= 16'd0;
            rep_idx   <= 16'd0;
        end else begin
            case (st)

            ST_POWER: begin
                if (pwr_cnt >= POWERUP_CYC) st <= ST_INIT;
                else                        pwr_cnt <= pwr_cnt + 24'd1;
            end

            ST_INIT: begin
                to_winit <= 32'd0;
                st       <= ST_WINIT;
            end

            ST_WINIT: begin
                to_winit <= to_winit + 32'd1;
                if (init_error) begin
                    top_err  <= init_err_code;
                    rep_err  <= 1'b1;
                    rstate   <= R_IDLE;
                    pc       <= 8'd0;
                    st       <= ST_REPORT;
                end else if (init_done) begin
                    st <= ST_MBR;
                end else if (to_winit == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end

            ST_MBR: begin
                to_wmbr <= 32'd0;
                st      <= ST_WMBR;
            end

            ST_WMBR: begin
                to_wmbr <= to_wmbr + 32'd1;
                if (mbr_parse_done) begin
                    if (mbr_err_code != `ERR_NONE) begin
                        top_err <= mbr_err_code;
                        rep_err <= 1'b1;
                        rstate  <= R_IDLE;
                        pc      <= 8'd0;
                        st      <= ST_REPORT;
                    end else begin
                        st <= ST_MOUNT;
                    end
                end else if (to_wmbr == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end

            ST_MOUNT: begin
                to_wmnt <= 32'd0;
                st      <= ST_WMNT;
            end

            ST_WMNT: begin
                to_wmnt <= to_wmnt + 32'd1;
                if (fs_mount_error) begin
                    top_err <= fs_err_code;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end else if (fs_mount_done) begin
                    st <= ST_SCAN;
                end else if (to_wmnt == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end

            ST_SCAN: begin
                ent_total <= 16'd0;
                to_wscan  <= 32'd0;
                st        <= ST_WSCAN;
            end

            ST_WSCAN: begin
                to_wscan <= to_wscan + 32'd1;


                if (ent_valid & ent_ready) begin

                    if (ent_total < MAX_ENT) begin
                        en_name[ent_total[2:0]] <= ent_name;
                        en_attr[ent_total[2:0]] <= ent_attr;
                        en_clus[ent_total[2:0]] <= ent_first_clus;
                        en_size[ent_total[2:0]] <= ent_size;
                        en_idx [ent_total[2:0]] <= ent_index;
                    end
                    ent_total <= ent_total + 16'd1;
                end

                if (scan_done) begin

                    if (dir_bad || (dir_err_code != `ERR_NONE)) begin
                        top_err <= (dir_err_code != `ERR_NONE) ? dir_err_code
                                                               : `ERR_MEDIA_INVALID;
                        rep_err <= 1'b1;
                        rstate  <= R_IDLE;
                        pc      <= 8'd0;
                        st      <= ST_REPORT;
                    end else begin
                        rep_err  <= 1'b0;
                        rstate   <= R_IDLE;
                        pc       <= 8'd0;
                        ent_cur  <= 3'd0;
                        to_rep   <= 32'd0;
                        st       <= ST_RPT;
                    end
                end else if (to_wscan == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end


            ST_RPT: begin
                rep_ok  <= 16'd0;
                rep_bad <= 16'd0;
                rep_idx <= 16'd0;
                to_rep  <= 32'd0;
                st      <= ST_RPTREQ;
            end

            ST_RPTREQ: begin
                to_rep <= 32'd0;
                if (rd_ready) st <= ST_RPTWAIT;
                else          st <= ST_RPTREQ;
            end

            ST_RPTWAIT: begin
                to_rep <= to_rep + 32'd1;
                if (rd_done) begin
                    if (rd_timeout || rd_crc16_err) begin
                        rep_bad <= rep_bad + 16'd1;
                        top_err <= `ERR_SD_IO;
                    end else begin
                        rep_ok  <= rep_ok + 16'd1;
                    end
                    if (rep_idx == (RPT_N - 16'd1)) begin
                        rstate  <= R_IDLE;
                        pc      <= 8'd0;
                        ent_cur <= 3'd0;
                        to_rep  <= 32'd0;
                        st      <= ST_REPORT;
                    end else begin
                        rep_idx <= rep_idx + 16'd1;
                        st      <= ST_RPTREQ;
                    end
                end else if (to_rep == TOP_TO) begin

                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    to_rep  <= 32'd0;
                    st      <= ST_REPORT;
                end
            end

            ST_REPORT: begin
                to_rep <= to_rep + 32'd1;
                if (to_rep == TOP_TO) st <= ST_ERR;
                case (rstate)
                R_IDLE: begin
                    if (rep_err) begin
                        rstate <= R_ERR;
                        pc     <= 8'd0;
                    end else begin
                        rstate <= R_HDR;
                        pc     <= 8'd0;
                        ent_cur<= 3'd0;
                    end
                end
                R_HDR: if (uart_ready) begin
                    if (pc == HDR_BYTES - 1) begin
                        if (ent_show == 4'd0) begin
                            rstate <= R_RPT;
                            pc     <= 8'd0;
                        end else begin
                            rstate <= R_ENT;
                            pc     <= 8'd0;
                            ent_cur<= 3'd0;
                        end
                    end else begin
                        pc <= pc + 8'd1;
                    end
                end
                R_ENT: if (uart_ready) begin
                    if (pc == ENT_BYTES - 1) begin
                        if (({1'b0, ent_cur} + 4'd1) >= ent_show) begin
                            rstate <= R_RPT;
                            pc     <= 8'd0;
                        end else begin
                            ent_cur <= ent_cur + 3'd1;
                            pc      <= 8'd0;
                        end
                    end else begin
                        pc <= pc + 8'd1;
                    end
                end
                R_RPT: if (uart_ready) begin
                    if (pc == RPT_BYTES - 1) begin

                        if (rep_bad != 16'd0) rstate <= R_ERR;
                        else                  rstate <= R_DONE;
                        pc <= 8'd0;
                    end else begin
                        pc <= pc + 8'd1;
                    end
                end
                R_ERR: if (uart_ready) begin
                    if (pc == ERR_BYTES - 1) rstate <= R_FIN;
                    else                     pc     <= pc + 8'd1;
                end
                R_DONE: if (uart_ready) begin
                    if (pc == DONE_BYTES - 1) rstate <= R_FIN;
                    else                      pc     <= pc + 8'd1;
                end
                R_FIN: begin
                    if (rep_err || (rep_bad != 16'd0)) st <= ST_ERR;
                    else                               st <= ST_OK;
                end
                default: rstate <= R_IDLE;
                endcase
            end
            ST_OK:  st <= ST_OK;
            ST_ERR: st <= ST_ERR;
            default: st <= ST_POWER;
            endcase
        end
    end


    reg [3:0] led_code;
    always @(*) begin
        case (st)
            ST_POWER : led_code = 4'h1;
            ST_INIT  : led_code = 4'h2;
            ST_WINIT : led_code = 4'h3;
            ST_MBR   : led_code = 4'h4;
            ST_WMBR  : led_code = 4'h4;
            ST_MOUNT : led_code = 4'h5;
            ST_WMNT  : led_code = 4'h5;
            ST_SCAN  : led_code = 4'h6;
            ST_WSCAN : led_code = 4'h6;
            ST_RPT   : led_code = 4'h9;
            ST_RPTREQ: led_code = 4'h9;
            ST_RPTWAIT:led_code = 4'h9;
            ST_REPORT: led_code = 4'h7;
            ST_OK    : led_code = 4'h8;
            default  : led_code = top_err[3:0];
        endcase
    end
    assign led = led_code;


    sd_initializer u_sd_initializer (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .start         (init_start),
        .sdhc          (sdhc),
        .init_done     (init_done),
        .init_error    (init_error),
        .err_code      (init_err_code),
        .err_detail    (),
        .retry_cnt     (),
        .dbg_state     (),
        .spi_cs_n      (init_cs_n),
        .spi_clk_div   (init_clk_div),
        .spi_tx_valid  (init_tx_valid),
        .spi_tx_data   (init_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );


    mbr_parser u_mbr_parser (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .start          (mbr_start),
        .parse_done     (mbr_parse_done),
        .err_code       (mbr_err_code),
        .err_detail     (mbr_err_detail),
        .dbg_state      (),
        .has_mbr        (mbr_has),
        .vol_base_lba   (mbr_vol_base),
        .part_secs      (mbr_part_secs),
        .sd_rd_addr     (mbr_sd_rd_addr),
        .sd_rd_len      (mbr_sd_rd_len),
        .sd_rd_en       (mbr_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (mbr_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail)
    );


    fat32_boot_parser u_fat32_boot_parser (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .start          (boot_start),
        .mount_done     (fs_mount_done),
        .mount_error    (fs_mount_error),
        .err_code       (fs_err_code),
        .err_detail     (fs_err_detail),
        .dbg_state      (),
        .bytes_per_sec  (fs_bps),
        .sec_per_clus   (fs_spc),
        .num_fats       (fs_nfat),
        .fat_start_lba  (fs_fat_lba),
        .root_clus      (fs_root_clus),
        .root_dir_lba   (fs_root_lba),
        .data_start_lba (fs_data_lba),
        .total_sec      (fs_tot_sec),
        .total_clus     (fs_tot_clus),
        .sd_rd_addr     (fs_sd_rd_addr),
        .sd_rd_len      (fs_sd_rd_len),
        .sd_rd_en       (fs_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (fs_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail)
    );


    fat32_directory_scanner u_fat32_directory_scanner (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .scan_en        (scan_en),
        .scan_done      (scan_done),
        .dir_bad        (dir_bad),
        .err_code       (dir_err_code),
        .err_detail     (dir_err_detail),
        .dbg_state      (),
        .sec_per_clus   (fs_spc),
        .root_clus      (fs_root_clus),
        .root_dir_lba   (fs_root_lba),
        .data_start_lba (fs_data_lba),
        .ent_name       (ent_name),
        .ent_attr       (ent_attr),
        .ent_first_clus (ent_first_clus),
        .ent_size       (ent_size),
        .ent_index      (ent_index),
        .ent_valid      (ent_valid),
        .ent_ready      (ent_ready),
        .sd_rd_addr     (dn_sd_rd_addr),
        .sd_rd_len      (dn_sd_rd_len),
        .sd_rd_en       (dn_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (dn_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail),
        .wk_cur_clus    (wk_cur_clus),
        .wk_start       (wk_start),
        .wk_rst_walk    (wk_rst_walk),
        .wk_busy        (wk_busy),
        .wk_done        (wk_done),
        .wk_next_clus   (wk_next_clus),
        .wk_eoc         (wk_eoc),
        .wk_error       (wk_error),
        .wk_err_code    (wk_err_code),
        .wk_err_detail  (wk_err_detail)
    );


    fat32_cluster_walker u_fat32_cluster_walker (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .rst_walk       (wk_rst_walk),
        .start          (wk_start),
        .cur_clus       (wk_cur_clus),
        .busy           (wk_busy),
        .done           (wk_done),
        .next_clus      (wk_next_clus),
        .eoc            (wk_eoc),
        .error          (wk_error),
        .err_code       (wk_err_code),
        .err_detail     (wk_err_detail),
        .hop_cnt        (),
        .dbg_state      (),
        .fat_start_lba  (fs_fat_lba),
        .total_clus     (fs_tot_clus),
        .sd_rd_addr     (wk_sd_rd_addr),
        .sd_rd_len      (wk_sd_rd_len),
        .sd_rd_en       (wk_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (wk_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail)
    );


    sd_sector_reader u_sd_sector_reader (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .sdhc          (sdhc),
        .rd_en         (bus_rd_en),
        .rd_addr       (rd_addr_to_reader),
        .rd_len        (bus_rd_len),
        .rd_ready      (rd_ready),
        .data          (rd_data),
        .data_valid    (rd_data_valid),
        .data_ready    (bus_data_ready),
        .data_last     (rd_data_last),
        .rd_done       (rd_done),
        .busy          (),
        .timeout_err   (rd_timeout),
        .crc16_err     (rd_crc16_err),
        .err_code      (rd_err_code),
        .err_detail    (rd_err_detail),
        .crc_rx        (),
        .dbg_state     (),
        .spi_cs_n      (rd_cs_n),
        .spi_clk_div   (rd_clk_div),
        .spi_tx_valid  (rd_tx_valid),
        .spi_tx_data   (rd_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );


    spi_master #(
        .CLK_FREQ (CLK_FREQ)
    ) u_spi_master (
        .clk        (clk),
        .rst_n      (rst_sync_n),
        .clk_div    (spi_clk_div),
        .cs_n       (sd_ncs),
        .tx_valid   (spi_tx_valid),
        .tx_data    (spi_tx_data),
        .tx_ready   (spi_tx_ready),
        .rx_data    (spi_rx_data),
        .rx_valid   (spi_rx_valid),
        .busy       (spi_busy),
        .sclk       (sd_dclk),
        .mosi       (sd_mosi),
        .miso       (sd_miso)
    );


    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_sync_n),
        .tx_valid  (uart_tx_valid),
        .tx_data   (uart_tx_data),
        .tx_ready  (uart_ready),
        .txd       (uart_txd)
    );

endmodule
