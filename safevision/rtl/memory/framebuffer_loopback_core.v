


`include "safevision_defs.vh"

module framebuffer_loopback_core #(
    parameter [31:0] SLOT_BASE   = `SV_IMG0_BASE,
    parameter [18:0] FRAME_PIX   = `SV_FRAME_PIXELS,
    parameter [5:0]  LOW_WATER   = 6'd48,
    parameter [15:0] GAP_TIMEOUT = 16'd4096,

    parameter [23:0] INIT_TO_CYC = 24'd16_000_000,
    parameter [23:0] WR_TO_CYC   = 24'd16_000_000,
    parameter [23:0] RD_TO_CYC   = 24'd16_000_000,
    parameter [15:0] WR_DRAIN_CYC = 16'd2048
)(
    input  wire        clk,
    input  wire        rst_n,


    output wire        sdram_req,
    output wire        sdram_wr,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire [3:0]  sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_rdata_valid,
    input  wire        sdram_ready,
    input  wire        sdram_init_done,


    output wire        rep_valid,
    output wire [7:0]  rep_data,
    input  wire        rep_ready,


    output reg         ok,
    output reg  [7:0]  err_code,
    output reg  [18:0] wr_px,
    output reg  [18:0] rd_px,
    output reg  [18:0] bad_px,
    output reg         crc_ok,
    output reg         slot_valid
);


    localparam [31:0] FRAME_BYTES = (FRAME_PIX * `SV_RGB565_BYTES_PER_PX);
    localparam integer RPT_LEN = 208;
    localparam [8:0]   RPT_LAST = 9'd207;


    localparam [15:0] LFSR_SEED = 16'hACE1;

    function [15:0] lfsr_next;
        input [15:0] s;
        begin
            lfsr_next = { s[14:0], (s[15] ^ s[13] ^ s[12] ^ s[10]) };
        end
    endfunction


    localparam [3:0] S_POWER    = 4'd0,
                     S_INIT     = 4'd1,
                     S_WR_START = 4'd2,
                     S_WR_RUN   = 4'd3,
                     S_RD_START = 4'd4,
                     S_RD_RUN   = 4'd5,
                     S_RD_WAIT  = 4'd6,
                     S_REPORT   = 4'd7,
                     S_OK       = 4'd8,
                     S_ERR      = 4'd9,
                     S_RD_DRAIN = 4'd10,
                     S_RAMP     = 4'd11;


    localparam [31:0] RAMPA_W    = 32'd4096;
    localparam [31:0] RAMPB_W    = 32'd4149;
    localparam [31:0] SCR_BYTE   = `SV_IMG0_BASE + (RAMPA_W << 2);
    localparam [31:0] SCRC_BYTE  = SCR_BYTE + 32'd16;
    localparam [31:0] SCR2_BYTE  = `SV_IMG0_BASE + (RAMPB_W << 2);
    localparam [15:0] RAMP_DRAIN = 16'd512;
    localparam [23:0] RAMP_TO_CYC= 24'd1_000_000;


    wire        fw_din_ready;
    wire        fw_wr_req;
    wire [31:0] fw_wr_addr;
    wire [31:0] fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid4;
    wire        dma_done_w;
    wire        fw_crc_ok_w;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire        fw_wr_done;
    wire        fw_wr_error;
    wire [7:0]  fw_err_code;
    wire [7:0]  fw_err_detail;


    wire        rdeng_ack;
    wire        rdeng_busy;
    wire [31:0] rdeng_data;
    wire        rdeng_data_valid;
    wire        dma_rd_req;
    wire [31:0] dma_rd_addr;
    wire [15:0] dma_rd_len;


    wire        rdeng_mem_req;
    wire [31:0] rdeng_mem_addr;
    wire        mem_req;
    wire        mem_wr;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_ready;
    wire [31:0] mem_rdata;
    wire        mem_rdata_valid;
    wire        mem_init_done;
    wire        mem_error;


    wire        pixfifo_wr;
    wire [15:0] pixfifo_din;
    wire        pixfifo_rd;
    wire [15:0] pixfifo_dout;
    wire        pixfifo_empty;
    wire [7:0]  pixfifo_cnt;
    wire [15:0] pixfifo_level = {8'b0, pixfifo_cnt};


    reg  [3:0]  st;
    reg  [23:0] init_to_cnt;
    reg  [23:0] wr_to_cnt;
    reg  [23:0] rd_to_cnt;
    reg         fw_start;
    reg         dma_start;
    reg  [18:0] wpx_sent;
    reg  [15:0] wlfsr;
    reg  [15:0] clfsr;
    reg         ck_v1, ck_v2;
    reg  [15:0] ck_pix, ck_exp;
    reg         ck_bad;
    reg  [3:0]  rd_settle;
    reg  [15:0] drain_cnt;
    reg         ramp_req, ramp_wr;
    reg  [31:0] ramp_addr, ramp_wdata;
    reg  [4:0]  ramp_ph;
    reg  [15:0] ramp_gap;
    reg  [23:0] ramp_to;
    reg  [5:0]  ramp_idx;
    reg  [5:0]  ramp_rdidx;


    reg  [31:0] amask;
    reg  [7:0]  af_idx;
    reg         af_set;
    reg  [31:0] av_val;
    reg  [63:0] cwq;
    reg  [63:0] bwq;

    wire [31:0] a_exp = RAMPA_W + {26'd0, ramp_rdidx};
    reg  [31:0] w0_q, w1_q;
    reg  [18:0] bad_first;
    reg         bf_set;
    reg  [2:0]  wcnt;
    reg         half_q;
    reg  [15:0] lo_q;
    reg  [8:0]  rpt_idx;
    reg         rpt_run;


    wire [8:0]  rpt_dn = rpt_idx - 9'd1;

    assign rep_valid = (st == S_REPORT) && rpt_run && rep_ready;
    wire   rep_fire  = rep_valid;


    wire [15:0] px_src        = wlfsr;
    wire        src_valid     = (st == S_WR_RUN) && (wpx_sent < FRAME_PIX);
    wire        px_src_accept = src_valid && fw_din_ready;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wlfsr    <= LFSR_SEED;
            wpx_sent <= 19'd0;
        end else if (st == S_WR_START) begin
            wlfsr    <= LFSR_SEED;
            wpx_sent <= 19'd0;
        end else if (px_src_accept) begin
            wlfsr    <= lfsr_next(wlfsr);
            wpx_sent <= wpx_sent + 19'd1;
        end
    end


    wire chk_active = (st == S_RD_RUN) || (st == S_RD_WAIT);
    assign pixfifo_rd = chk_active && !pixfifo_empty;
    wire   chk_fire   = pixfifo_rd;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ck_v1 <= 1'b0; ck_v2 <= 1'b0; ck_bad <= 1'b0;
            ck_pix<= 16'd0; ck_exp<= 16'd0;
            clfsr <= LFSR_SEED; rd_px <= 19'd0; bad_px <= 19'd0;
            wcnt <= 3'd0; half_q <= 1'b0; lo_q <= 16'd0;
            w0_q <= 32'd0; w1_q <= 32'd0;
            bad_first <= 19'd0; bf_set <= 1'b0;
        end else if (st == S_RD_START) begin
            ck_v1 <= 1'b0; ck_v2 <= 1'b0; ck_bad <= 1'b0;
            ck_pix<= 16'd0; ck_exp<= 16'd0;
            clfsr <= LFSR_SEED; rd_px <= 19'd0; bad_px <= 19'd0;
            wcnt <= 3'd0; half_q <= 1'b0; lo_q <= 16'd0;
            w0_q <= 32'd0; w1_q <= 32'd0;
            bad_first <= 19'd0; bf_set <= 1'b0;
        end else begin

            ck_v1  <= chk_fire;
            ck_pix <= pixfifo_dout;
            ck_exp <= clfsr;
            if (chk_fire) begin
                clfsr <= lfsr_next(clfsr);
                rd_px <= rd_px + 19'd1;
            end

            ck_v2  <= ck_v1;
            ck_bad <= ck_v1 && (ck_pix !== ck_exp);

            if (ck_bad) bad_px <= bad_px + 19'd1;

            if (ck_bad && !bf_set) begin bad_first <= rd_px; bf_set <= 1'b1; end


            if (chk_fire) begin
                if (!half_q) begin
                    lo_q   <= pixfifo_dout;
                    half_q <= 1'b1;
                end else begin
                    half_q <= 1'b0;
                    if (wcnt == 3'd0)      w0_q <= {pixfifo_dout, lo_q};
                    else if (wcnt == 3'd1) w1_q <= {pixfifo_dout, lo_q};
                    if (wcnt < 3'd3) wcnt <= wcnt + 3'd1;
                end
            end
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= S_POWER;
            init_to_cnt <= 24'd0;
            wr_to_cnt   <= 24'd0;
            rd_to_cnt   <= 24'd0;
            fw_start    <= 1'b0;
            dma_start   <= 1'b0;
            rd_settle   <= 4'd0;
            drain_cnt   <= 16'd0;
            ramp_req    <= 1'b0;
            ramp_wr     <= 1'b0;
            ramp_ph     <= 5'd0;
            ramp_gap    <= 16'd0;
            ramp_to     <= 24'd0;
            ramp_idx    <= 6'd0;
            ramp_rdidx  <= 6'd0;
            amask       <= 32'd0;
            af_idx      <= 8'hFF;
            af_set      <= 1'b0;
            av_val      <= 32'd0;
            rpt_idx     <= RPT_LAST;
            rpt_run     <= 1'b0;
            ok          <= 1'b0;
            err_code    <= 8'h00;
            wr_px       <= 19'd0;
            crc_ok      <= 1'b0;
            slot_valid  <= 1'b0;
        end else begin

            fw_start  <= 1'b0;
            dma_start <= 1'b0;


            if (mem_error && (err_code == 8'h00)) err_code <= 8'h06;

            case (st)

            S_POWER: begin
                st <= S_INIT;
            end
            S_INIT: begin
                if (mem_init_done)                 st <= S_RAMP;
                else if (init_to_cnt >= INIT_TO_CYC) begin
                    err_code <= 8'h01;
                    st       <= S_REPORT;
                end else init_to_cnt <= init_to_cnt + 24'd1;
            end


            S_RAMP: begin
                if (mem_error || (ramp_to >= RAMP_TO_CYC)) begin
                    err_code <= 8'h06;
                    st       <= S_REPORT;
                end else begin

                    if (mem_ready || mem_rdata_valid) ramp_to <= 24'd0;
                    else                              ramp_to <= ramp_to + 24'd1;

                    case (ramp_ph)

                    5'd0: begin
                        ramp_req   <= 1'b0; ramp_wr <= 1'b0;
                        ramp_addr  <= SCR_BYTE;
                        ramp_wdata <= RAMPA_W;
                        ramp_idx   <= 6'd0;
                        ramp_ph    <= 5'd1;
                    end

                    5'd1: begin ramp_req <= 1'b1; ramp_wr <= 1'b1; ramp_ph <= 5'd2; end
                    5'd2: if (mem_ready) begin
                              ramp_addr  <= ramp_addr  + 32'd4;
                              ramp_wdata <= ramp_wdata + 32'd1;
                              if (ramp_idx == 6'd31) begin
                                  ramp_req <= 1'b0;
                                  ramp_ph  <= 5'd3;
                              end else ramp_idx <= ramp_idx + 6'd1;
                          end

                    5'd3: if (ramp_gap >= RAMP_DRAIN) begin
                              ramp_gap   <= 16'd0;
                              ramp_addr  <= SCR_BYTE;
                              ramp_rdidx <= 6'd0;
                              amask      <= 32'd0;
                              af_idx     <= 8'hFF;
                              af_set     <= 1'b0;
                              av_val     <= 32'd0;
                              ramp_ph    <= 5'd4;
                          end else ramp_gap <= ramp_gap + 16'd1;

                    5'd4: begin ramp_req <= 1'b1; ramp_wr <= 1'b0; ramp_ph <= 5'd5; end
                    5'd5: if (mem_ready) begin ramp_req <= 1'b0; ramp_ph <= 5'd6; end
                    5'd6: if (mem_rdata_valid) begin

                              amask <= {(mem_rdata === a_exp), amask[31:1]};
                              if (!af_set && (mem_rdata !== a_exp)) begin
                                  af_idx <= {2'b0, ramp_rdidx};
                                  av_val <= mem_rdata;
                                  af_set <= 1'b1;
                              end
                              ramp_addr <= ramp_addr + 32'd4;
                              if (ramp_rdidx == 6'd31) begin
                                  ramp_rdidx <= 6'd0;
                                  ramp_addr  <= SCRC_BYTE;
                                  ramp_ph    <= 5'd7;
                              end else begin
                                  ramp_rdidx <= ramp_rdidx + 6'd1;
                                  ramp_ph    <= 5'd4;
                              end
                          end


                    5'd7: begin ramp_req <= 1'b1; ramp_wr <= 1'b0; ramp_ph <= 5'd8; end
                    5'd8: if (mem_ready) begin ramp_req <= 1'b0; ramp_ph <= 5'd9; end
                    5'd9: if (mem_rdata_valid) begin
                              cwq <= {cwq[47:0], mem_rdata[15:0]};
                              ramp_addr      <= ramp_addr + 32'd4;
                              if (ramp_rdidx == 6'd3) begin
                                  ramp_rdidx <= 6'd0;
                                  ramp_idx   <= 6'd0;
                                  ramp_ph    <= 5'd10;
                              end else begin
                                  ramp_rdidx <= ramp_rdidx + 6'd1;
                                  ramp_ph    <= 5'd7;
                              end
                          end

                    5'd10: begin
                        ramp_addr  <= SCR2_BYTE;
                        ramp_wdata <= RAMPB_W;
                        ramp_idx   <= 6'd0;
                        ramp_ph    <= 5'd11;
                    end

                    5'd11: begin ramp_req <= 1'b1; ramp_wr <= 1'b1; ramp_ph <= 5'd12; end
                    5'd12: if (mem_ready) begin
                              ramp_addr  <= ramp_addr  + 32'd4;
                              ramp_wdata <= ramp_wdata + 32'd1;
                              if (ramp_idx == 6'd3) begin
                                  ramp_req <= 1'b0;
                                  ramp_ph  <= 5'd13;
                              end else ramp_idx <= ramp_idx + 6'd1;
                          end

                    5'd13: if (ramp_gap >= RAMP_DRAIN) begin
                               ramp_gap   <= 16'd0;
                               ramp_addr  <= SCR2_BYTE;
                               ramp_rdidx <= 6'd0;
                               ramp_ph    <= 5'd14;
                           end else ramp_gap <= ramp_gap + 16'd1;

                    5'd14: begin ramp_req <= 1'b1; ramp_wr <= 1'b0; ramp_ph <= 5'd15; end
                    5'd15: if (mem_ready) begin ramp_req <= 1'b0; ramp_ph <= 5'd16; end
                    5'd16: if (mem_rdata_valid) begin
                               bwq <= {bwq[47:0], mem_rdata[15:0]};
                               ramp_addr      <= ramp_addr + 32'd4;
                               if (ramp_rdidx == 6'd3) ramp_ph <= 5'd17;
                               else begin
                                   ramp_rdidx <= ramp_rdidx + 6'd1;
                                   ramp_ph    <= 5'd14;
                               end
                           end

                    5'd17: begin ramp_ph <= 5'd0; st <= S_WR_START; end
                    default: begin ramp_req <= 1'b0; ramp_wr <= 1'b0;
                                   ramp_ph  <= 5'd0; st <= S_WR_START; end
                    endcase
                end
            end

            S_WR_START: begin
                fw_start <= 1'b1;
                st       <= S_WR_RUN;
            end
            S_WR_RUN: begin
                if (fw_wr_error) begin
                    err_code  <= 8'h02;
                    st        <= S_REPORT;
                end else if (fw_wr_done) begin
                    wr_px     <= fw_px_cnt;
                    crc_ok    <= fw_crc_ok_w;
                    slot_valid<= fw_slot_valid4[0];
                    if (fw_crc_ok_w && fw_slot_valid4[0]) begin
                        drain_cnt <= 16'd0;
                        st        <= S_RD_DRAIN;
                    end else begin
                        err_code <= 8'h03;
                        st       <= S_REPORT;
                    end
                end else if (wr_to_cnt >= WR_TO_CYC) begin
                    err_code  <= 8'h04;
                    st        <= S_REPORT;
                end else wr_to_cnt <= wr_to_cnt + 24'd1;
            end

            S_RD_DRAIN: begin
                if (drain_cnt >= WR_DRAIN_CYC) st <= S_RD_START;
                else                           drain_cnt <= drain_cnt + 16'd1;
            end

            S_RD_START: begin
                dma_start <= 1'b1;
                rd_settle <= 4'd0;
                st        <= S_RD_RUN;
            end
            S_RD_RUN: begin
                if (dma_done_w) begin
                    rd_to_cnt <= 24'd0;
                    st        <= S_RD_WAIT;
                end else if (rd_to_cnt >= RD_TO_CYC) begin
                    err_code <= 8'h05;
                    st       <= S_REPORT;
                end else rd_to_cnt <= rd_to_cnt + 24'd1;
            end

            S_RD_WAIT: begin
                if ((rd_px >= FRAME_PIX) && pixfifo_empty) begin

                    if (rd_settle >= 4'd8) begin
                        if (bad_px != 19'd0) err_code <= 8'h07;
                        st <= S_REPORT;
                    end else rd_settle <= rd_settle + 4'd1;
                end else if (rd_to_cnt >= RD_TO_CYC) begin
                    err_code <= 8'h05;
                    st       <= S_REPORT;
                end else rd_to_cnt <= rd_to_cnt + 24'd1;
            end

            S_REPORT: begin
                if (!rpt_run) begin
                    rpt_run <= 1'b1;
                    rpt_idx <= RPT_LAST;
                end else if (rep_fire) begin
                    if (rpt_idx == 9'd0) begin
                        rpt_run <= 1'b0;
                        if (err_code == 8'h00) begin
                            ok <= 1'b1;
                            st <= S_OK;
                        end else st <= S_ERR;
                    end else rpt_idx <= rpt_dn;
                end
            end
            S_OK : st <= S_OK;
            S_ERR: st <= S_ERR;
            default: st <= S_POWER;
            endcase
        end
    end


    function [7:0] hx;
        input [3:0] n;
        begin
            hx = (n < 4'd10) ? (8'h30 + {4'b0, n}) : (8'h37 + {4'b0, n});
        end
    endfunction

    function [15:0] hex8;
        input [7:0] v;
        begin
            hex8 = { hx(v[7:4]), hx(v[3:0]) };
        end
    endfunction

    function [31:0] hex16;
        input [15:0] v;
        begin
            hex16 = { hx(v[15:12]), hx(v[11:8]), hx(v[7:4]), hx(v[3:0]) };
        end
    endfunction

    function [47:0] hex24;
        input [23:0] v;
        begin
            hex24 = { hx(v[23:20]), hx(v[19:16]), hx(v[15:12]),
                      hx(v[11:8]),  hx(v[7:4]),   hx(v[3:0]) };
        end
    endfunction

    function [63:0] hex32;
        input [31:0] v;
        begin
            hex32 = { hx(v[31:28]), hx(v[27:24]), hx(v[23:20]), hx(v[19:16]),
                      hx(v[15:12]), hx(v[11:8]),  hx(v[7:4]),   hx(v[3:0]) };
        end
    endfunction


    wire [23:0] wr_px24 = { 5'b0, wr_px };
    wire [23:0] rd_px24 = { 5'b0, rd_px };
    wire [23:0] bad24   = { 5'b0, bad_px };


    wire [8*12-1:0] rpt_l1 = { "SV-FB-LOOP", 8'h0D, 8'h0A };

    wire [8*9-1:0]  rpt_l2 = { "INIT=", hex8({7'b0, mem_init_done}), 8'h0D, 8'h0A };

    wire [8*24-1:0] rpt_l3 = { "WR=",  hex24(wr_px24), " CRC=", hex8({7'b0, crc_ok}),
                               " SV=", hex8({7'b0, slot_valid}), 8'h0D, 8'h0A };

    wire [8*22-1:0] rpt_l4 = { "RD=", hex24(rd_px24), " BAD=", hex24(bad24), 8'h0D, 8'h0A };

    wire [8*25-1:0] rpt_l5 = { "W0=", hex32(w0_q), " W1=", hex32(w1_q), 8'h0D, 8'h0A };

    wire [8*13-1:0] rpt_l6 = { "AM=", hex32(amask), 8'h0D, 8'h0A };

    wire [8*7-1:0]  rpt_l7 = { "AF=", hex8(af_idx), 8'h0D, 8'h0A };

    wire [8*13-1:0] rpt_l8 = { "AV=", hex32(av_val), 8'h0D, 8'h0A };


    wire [8*33-1:0] rpt_l9 = { "C0=", hex16(cwq[63:48]), " C1=", hex16(cwq[47:32]),
                               " C2=", hex16(cwq[31:16]), " C3=", hex16(cwq[15:0]), 8'h0D, 8'h0A };

    wire [8*33-1:0] rpt_l10 = { "B0=", hex16(bwq[63:48]), " B1=", hex16(bwq[47:32]),
                                " B2=", hex16(bwq[31:16]), " B3=", hex16(bwq[15:0]), 8'h0D, 8'h0A };

    wire [8*11-1:0] rpt_l11 = { "BF=", hex24({5'b0, bad_first}), 8'h0D, 8'h0A };

    wire [8*6-1:0]  rpt_l12 = { "DONE", 8'h0D, 8'h0A };


    wire [8*RPT_LEN-1:0] rpt_vec = { rpt_l1, rpt_l2, rpt_l3, rpt_l4, rpt_l5,
                                     rpt_l6, rpt_l7, rpt_l8, rpt_l9, rpt_l10,
                                     rpt_l11, rpt_l12 };


    reg  [8*16-1:0] blk_q;
    reg  [4:0]      blk_nxt;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blk_q <= {8*16{1'b0}};
        else if (st == S_REPORT) begin
            if (!rpt_run)
                blk_q <= rpt_vec[ {RPT_LAST[8:4], 7'b0000000} +: 128 ];
            else if (rep_fire && (rpt_idx != 9'd0))
                blk_q <= rpt_vec[ {blk_nxt, 7'b0000000} +: 128 ];
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blk_nxt <= 5'd12;
        else if (st == S_REPORT) begin
            if (!rpt_run)                    blk_nxt <= RPT_LAST[8:4];
            else if (rep_fire) begin
                if (rpt_idx[3:0] == 4'd1)    blk_nxt <= blk_nxt - 5'd1;
            end
        end
    end


    assign rep_data = blk_q[ {rpt_idx[3:0], 3'b000} +: 8 ];


    frame_writer #(
        .GAP_TIMEOUT (GAP_TIMEOUT)
    ) u_fw (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (fw_start),
        .slot_sel   (2'd0),
        .slot_base  (SLOT_BASE),
        .din        (px_src),
        .din_valid  (src_valid),
        .din_ready  (fw_din_ready),
        .wr_req     (fw_wr_req),
        .wr_addr    (fw_wr_addr),
        .wr_data    (fw_wr_data),
        .wr_len     (fw_wr_len),
        .wr_ready   (mem_ready),
        .wr_done    (fw_wr_done),
        .slot_valid (fw_slot_valid4),
        .crc_ok     (fw_crc_ok_w),
        .crc_value  (fw_crc_value),
        .px_cnt     (fw_px_cnt),
        .wr_error   (fw_wr_error),
        .err_code   (fw_err_code),
        .err_detail (fw_err_detail)
    );


    wire wr_phase   = (st == S_WR_START) || (st == S_WR_RUN);
    wire ramp_phase = (st == S_RAMP);

    assign mem_req   = ramp_phase ? ramp_req   : (wr_phase ? fw_wr_req  : rdeng_mem_req);
    assign mem_wr    = ramp_phase ? ramp_wr    : (wr_phase ? 1'b1       : 1'b0);
    assign mem_addr  = ramp_phase ? ramp_addr  : (wr_phase ? fw_wr_addr : rdeng_mem_addr);
    assign mem_wdata = ramp_phase ? ramp_wdata : (wr_phase ? fw_wr_data : 32'd0);
    assign mem_wstrb = ramp_phase ? (ramp_wr ? 4'hF : 4'h0) : (wr_phase ? 4'hF : 4'h0);

    mem_read_burst u_rdeng (
        .clk             (clk),
        .rst_n           (rst_n),
        .req             (dma_rd_req),
        .addr            (dma_rd_addr),
        .len             (dma_rd_len),
        .ack             (rdeng_ack),
        .busy            (rdeng_busy),
        .data            (rdeng_data),
        .data_valid      (rdeng_data_valid),
        .mem_req         (rdeng_mem_req),
        .mem_addr        (rdeng_mem_addr),
        .mem_ready       (mem_ready),
        .mem_rdata       (mem_rdata),
        .mem_rdata_valid (mem_rdata_valid)
    );

    video_read_dma #(
        .PIX_DEPTH     (128),
        .LOW_WATER     (LOW_WATER)
    ) u_dma (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (dma_start),
        .frame_base    (SLOT_BASE),
        .pix_fifo_level(pixfifo_level),
        .rd_req        (dma_rd_req),
        .rd_addr       (dma_rd_addr),
        .rd_len        (dma_rd_len),
        .rd_ack        (rdeng_ack),
        .rd_busy       (rdeng_busy),
        .rd_data       (rdeng_data),
        .rd_data_valid (rdeng_data_valid),
        .fifo_wr_data  (pixfifo_din),
        .fifo_wr_en    (pixfifo_wr),
        .rd_bytes_cnt  (),
        .active        (),
        .done          (dma_done_w)
    );

    sync_fifo #(
        .W              (16),
        .DEPTH          (128),
        .ALMOST_FULL_TH (96),
        .ALMOST_EMPTY_TH(8)
    ) u_pixfifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (pixfifo_wr),
        .din          (pixfifo_din),
        .full         (),
        .almost_full  (),
        .rd_en        (pixfifo_rd),
        .dout         (pixfifo_dout),
        .empty        (pixfifo_empty),
        .almost_empty (),
        .data_count   (pixfifo_cnt)
    );

    mem_ctrl u_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .init_done         (mem_init_done),
        .req               (mem_req),
        .wr                (mem_wr),
        .addr              (mem_addr),
        .wdata             (mem_wdata),
        .wstrb             (mem_wstrb),
        .rdata             (mem_rdata),
        .rdata_valid       (mem_rdata_valid),
        .ready             (mem_ready),
        .mem_error         (mem_error),
        .sdram_req         (sdram_req),
        .sdram_wr          (sdram_wr),
        .sdram_addr        (sdram_addr),
        .sdram_wdata       (sdram_wdata),
        .sdram_wstrb       (sdram_wstrb),
        .sdram_rdata       (sdram_rdata),
        .sdram_rdata_valid (sdram_rdata_valid),
        .sdram_ready       (sdram_ready),
        .sdram_init_done   (sdram_init_done)
    );

endmodule
