


module top_sdram_loopback #(
    parameter integer CLK_FREQ      = 50_000_000,
    parameter integer MEM_CLK_FREQ  = 125_000_000,
    parameter integer BAUD          = 115200,

    parameter [23:0]  POWERUP_CYC   = 24'd2_500_000,
    parameter [23:0]  INIT_TO_CYC   = 24'd2_000_000,

    parameter [20:0]  BASE_ADDR     = 21'd0,
    parameter [20:0]  TEST_WORDS    = 21'd1024,
    parameter integer ADDR_SHIFT    = 11,
    parameter integer ADDR_LOWSTEP  = 1,
    parameter [31:0]  ROUNDS        = 32'd27_000_000,

    parameter integer BURST_N       = 128,
    parameter integer BURST_GAP     = 16,

    parameter [15:0]  WR_DRAIN_CYC  = 16'd512,
    parameter [19:0]  RD_WAIT_TO_CYC= 20'd200_000
)(

    input  wire        clk,
    input  wire        rst_n,
    output wire        uart_txd,
    output wire [3:0]  led
);


    wire rst_ref_n;
    wire pll_locked;
    wire rst_mem_n;
    wire rst_mem;

    reset_sync u_rst_ref (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_ref_n)
    );


    wire ext_mem_clk;
    wire ext_mem_clk_sft;

    sv_system_pll u_sys_pll (
        .refclk   (clk),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (),
        .clk1_out (ext_mem_clk),
        .clk2_out (ext_mem_clk_sft)
    );

    reset_sync u_rst_mem (
        .clk        (ext_mem_clk),
        .async_rst_n(rst_ref_n & pll_locked),
        .rst_n      (rst_mem_n)
    );

    assign rst_mem = ~rst_mem_n;


    wire        sdr_init_done;
    wire        sdr_init_ref_vld;
    wire        sdr_busy;
    wire        app_wr_en;
    wire [20:0] app_wr_addr;
    wire [31:0] app_wr_din;
    wire [3:0]  app_wr_dm;
    wire        app_rd_en;
    wire [20:0] app_rd_addr;
    wire        sdr_rd_en;
    wire [31:0] sdr_rd_dout;


    wire        uart_tx_ready;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;


    localparam [3:0] ST_POWER    = 4'd0,
                     ST_INITWAIT = 4'd1,
                     ST_WRITE    = 4'd2,
                     ST_DRAIN    = 4'd3,
                     ST_READ     = 4'd4,
                     ST_RDWAIT   = 4'd5,
                     ST_ROUND    = 4'd9,
                     ST_REPORT   = 4'd6,
                     ST_OK       = 4'd7,
                     ST_ERR      = 4'd8;


    localparam integer PERIOD = BURST_N + BURST_GAP;


    localparam integer RPT_LEN  = 190;
    localparam [7:0]   RPT_LAST = RPT_LEN - 1;


    localparam [7:0] SHIFT_BYTE  = ADDR_SHIFT;
    localparam [3:0] LOWSTEP_NIB = ADDR_LOWSTEP;

    localparam       LOWSTEP_EN  = (ADDR_LOWSTEP != 0);

    reg  [3:0]  st;
    reg  [23:0] pwr_cnt;
    reg  [23:0] init_to_cnt;
    reg  [15:0] drain_cnt;
    reg  [19:0] rdwait_to_cnt;
    reg  [7:0]  err_code;
    reg  [7:0]  rpt_idx;
    reg         rpt_run;
    reg  [8*44-1:0] rpt_line_q;
    reg  [5:0]  rpt_byte_pos_q;
    reg         rpt_line_valid;
    reg  [7:0]  rpt_byte_q;
    reg         rpt_byte_valid;
    reg  [7:0]  t_wr;
    reg  [7:0]  t_rd;
    reg  [20:0] wr_i;
    reg  [20:0] rd_i;
    reg  [20:0] cap_cnt;
    reg  [15:0] bad_cnt;


    reg  [31:0] rnd;
    reg  [2:0]  pat_mode;
    reg  [39:0] tot_cnt;


    reg         sample_v;
    reg  [20:0] sample_addr;
    reg  [31:0] sample_data;
    reg  [2:0]  sample_mode;
    reg         expect_v;
    reg  [20:0] expect_addr;
    reg  [31:0] expect_data;
    reg  [31:0] expect_pat;
    reg         cmp_v;
    reg  [3:0]  cmp_bad_bytes;
    reg  [20:0] cmp_addr;
    reg  [31:0] cmp_exp;
    reg  [31:0] cmp_act;
    reg  [20:0] checked_cnt;


    reg         bad0_set;
    reg  [31:0] bad0_rnd;
    reg  [20:0] bad0_addr;
    reg  [31:0] bad0_exp;
    reg  [31:0] bad0_act;


    wire [20:0] wr_addr  = BASE_ADDR + (wr_i    << ADDR_SHIFT) + (LOWSTEP_EN ? wr_i    : 21'd0);
    wire [20:0] rd_addr  = BASE_ADDR + (rd_i    << ADDR_SHIFT) + (LOWSTEP_EN ? rd_i    : 21'd0);
    wire [20:0] cap_addr = BASE_ADDR + (cap_cnt << ADDR_SHIFT) + (LOWSTEP_EN ? cap_cnt : 21'd0);


    wire [31:0] pat_wr;
    wire [31:0] pat_rd;
    sdr_pat_gen u_pat_wr ( .addr(wr_addr),     .mode(pat_mode),   .pat(pat_wr) );
    sdr_pat_gen u_pat_rd ( .addr(sample_addr), .mode(sample_mode), .pat(pat_rd) );


    assign app_wr_en = (st == ST_WRITE) && (t_wr < BURST_N) && (wr_i < TEST_WORDS);
    assign app_rd_en = (st == ST_READ ) && (t_rd < BURST_N) && (rd_i < TEST_WORDS);

    assign app_wr_addr = wr_addr;
    assign app_wr_din  = pat_wr;
    assign app_wr_dm   = 4'b0000;
    assign app_rd_addr = rd_addr;


    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            t_wr <= 8'd0;
            wr_i <= 21'd0;
        end else if (st == ST_ROUND) begin
            t_wr <= 8'd0;
            wr_i <= 21'd0;
        end else if (st == ST_WRITE) begin
            if (t_wr == PERIOD - 1) t_wr <= 8'd0;
            else                    t_wr <= t_wr + 8'd1;
            if (app_wr_en)          wr_i <= wr_i + 21'd1;
        end
    end


    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            t_rd <= 8'd0;
            rd_i <= 21'd0;
        end else if (st == ST_ROUND) begin
            t_rd <= 8'd0;
            rd_i <= 21'd0;
        end else if (st == ST_READ) begin
            if (t_rd == PERIOD - 1) t_rd <= 8'd0;
            else                    t_rd <= t_rd + 8'd1;
            if (app_rd_en)          rd_i <= rd_i + 21'd1;
        end
    end


    wire rd_capture = sdr_rd_en && ((st == ST_READ) || (st == ST_RDWAIT)) &&
                      (cap_cnt < TEST_WORDS);

    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            cap_cnt       <= 21'd0;
            checked_cnt   <= 21'd0;
            bad_cnt       <= 16'd0;
            tot_cnt       <= 40'd0;
            bad0_set      <= 1'b0;
            bad0_rnd      <= 32'd0;
            bad0_addr     <= 21'd0;
            bad0_exp      <= 32'd0;
            bad0_act      <= 32'd0;
            sample_v      <= 1'b0;
            sample_addr   <= 21'd0;
            sample_data   <= 32'd0;
            sample_mode   <= 3'd0;
            expect_v      <= 1'b0;
            expect_addr   <= 21'd0;
            expect_data   <= 32'd0;
            expect_pat    <= 32'd0;
            cmp_v         <= 1'b0;
            cmp_bad_bytes <= 4'b0000;
            cmp_addr      <= 21'd0;
            cmp_exp       <= 32'd0;
            cmp_act       <= 32'd0;
        end else if (st == ST_ROUND) begin

            cap_cnt       <= 21'd0;
            checked_cnt   <= 21'd0;
            bad_cnt       <= 16'd0;
            sample_v      <= 1'b0;
            expect_v      <= 1'b0;
            cmp_v         <= 1'b0;
            cmp_bad_bytes <= 4'b0000;
        end else begin

            sample_v <= rd_capture;
            expect_v <= sample_v;
            cmp_v    <= expect_v;


            if (rd_capture) begin
                cap_cnt     <= cap_cnt + 21'd1;
                tot_cnt     <= tot_cnt + 40'd1;
                sample_addr <= cap_addr;
                sample_mode <= pat_mode;
                sample_data <= sdr_rd_dout;
            end


            if (sample_v) begin
                expect_addr <= sample_addr;
                expect_data <= sample_data;
                expect_pat  <= pat_rd;
            end


            if (expect_v) begin
                cmp_addr <= expect_addr;
                cmp_exp  <= expect_pat;
                cmp_act  <= expect_data;
                cmp_bad_bytes <= {
                    (expect_data[31:24] != expect_pat[31:24]),
                    (expect_data[23:16] != expect_pat[23:16]),
                    (expect_data[15:8]  != expect_pat[15:8]),
                    (expect_data[7:0]   != expect_pat[7:0])
                };
            end


            if (cmp_v) begin
                checked_cnt <= checked_cnt + 21'd1;
                if (|cmp_bad_bytes) begin
                    bad_cnt <= bad_cnt + 16'd1;
                    if (!bad0_set) begin
                        bad0_rnd  <= rnd + 32'd1;
                        bad0_addr <= cmp_addr;
                        bad0_exp  <= cmp_exp;
                        bad0_act  <= cmp_act;
                        bad0_set  <= 1'b1;
                    end
                end
            end
        end
    end


    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            st            <= ST_POWER;
            pwr_cnt       <= 24'd0;
            init_to_cnt   <= 24'd0;
            drain_cnt     <= 16'd0;
            rdwait_to_cnt <= 20'd0;
            err_code      <= 8'h00;
            rpt_idx       <= RPT_LAST;
            rpt_run       <= 1'b0;
            rnd           <= 32'd0;
            pat_mode      <= 3'd0;
        end else begin
            case (st)

            ST_POWER: begin
                if (pwr_cnt >= POWERUP_CYC) st <= ST_INITWAIT;
                else                        pwr_cnt <= pwr_cnt + 24'd1;
            end

            ST_INITWAIT: begin
                if (sdr_init_done)                 st <= ST_WRITE;
                else if (init_to_cnt >= INIT_TO_CYC) begin
                    err_code <= 8'h01;
                    st       <= ST_ERR;
                end else init_to_cnt <= init_to_cnt + 24'd1;
            end

            ST_WRITE: begin
                if (wr_i >= TEST_WORDS) st <= ST_DRAIN;
            end

            ST_DRAIN: begin
                if (drain_cnt >= WR_DRAIN_CYC) st <= ST_READ;
                else                           drain_cnt <= drain_cnt + 16'd1;
            end

            ST_READ: begin
                if (rd_i >= TEST_WORDS) begin
                    rdwait_to_cnt <= 20'd0;
                    st            <= ST_RDWAIT;
                end
            end

            ST_RDWAIT: begin
                if (checked_cnt >= TEST_WORDS) begin

                    if ((bad_cnt != 16'd0) || ((rnd + 32'd1) >= ROUNDS)) st <= ST_REPORT;
                    else                                                  st <= ST_ROUND;
                end else if (rdwait_to_cnt >= RD_WAIT_TO_CYC) begin
                    err_code <= 8'h02;
                    st       <= ST_ERR;
                end else rdwait_to_cnt <= rdwait_to_cnt + 20'd1;
            end


            ST_ROUND: begin
                rnd        <= rnd + 32'd1;
                pat_mode   <= (pat_mode == 3'd5) ? 3'd0 : (pat_mode + 3'd1);
                drain_cnt  <= 16'd0;
                st         <= ST_WRITE;
            end

            ST_REPORT: begin
                if (!rpt_run) begin
                    rpt_run <= 1'b1;
                    rpt_idx <= RPT_LAST;
                end else if (rpt_byte_valid && uart_tx_ready) begin
                    if (rpt_idx == 8'd0) begin
                        rpt_run <= 1'b0;
                        if (bad_cnt != 16'd0) begin
                            err_code <= 8'h03;
                            st       <= ST_ERR;
                        end else st <= ST_OK;
                    end else rpt_idx <= rpt_idx - 8'd1;
                end
            end
            ST_OK : st <= ST_OK;
            ST_ERR: st <= ST_ERR;
            default: st <= ST_POWER;
            endcase
        end
    end


    reg [3:0] led_code;
    always @(*) begin
        case (st)
            ST_POWER   : led_code = 4'h1;
            ST_INITWAIT: led_code = 4'h2;
            ST_WRITE   : led_code = 4'h3;
            ST_DRAIN   : led_code = 4'h4;
            ST_READ    : led_code = 4'h5;
            ST_RDWAIT  : led_code = 4'h6;
            ST_ROUND   : led_code = 4'h3;
            ST_REPORT  : led_code = 4'h7;
            ST_OK      : led_code = 4'h8;
            default    : led_code = err_code[3:0];
        endcase
    end

    assign led = led_code;


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

    function [79:0] hex40;
        input [39:0] v;
        begin
            hex40 = { hx(v[39:36]), hx(v[35:32]), hx(v[31:28]), hx(v[27:24]), hx(v[23:20]),
                      hx(v[19:16]), hx(v[15:12]), hx(v[11:8]),  hx(v[7:4]),   hx(v[3:0]) };
        end
    endfunction


    wire [23:0] base24   = { 3'b0, BASE_ADDR  };
    wire [23:0] n24      = { 3'b0, TEST_WORDS };
    wire [23:0] bad0_rep = bad0_set ? { 3'b0, bad0_addr } : 24'hFFFFFF;
    wire [31:0] exp_rep  = bad0_set ? bad0_exp : 32'd0;
    wire [31:0] act_rep  = bad0_set ? bad0_act : 32'd0;
    wire [31:0] rnd_rep  = bad0_set ? bad0_rnd : 32'hFFFFFFFF;
    wire [31:0] rnd_cur  = rnd + 32'd1;


    wire [8*15-1:0] rpt_l1 = { "SV-SDRAM-LOOP", 8'h0D, 8'h0A };
    wire [8*17-1:0] rpt_l2 = { "INIT=", hex8({7'b0, sdr_init_done}),
                               " LOCK=", hex8({7'b0, pll_locked}), 8'h0D, 8'h0A };

    wire [8*30-1:0] rpt_l3 = { "CFG=", hex8(SHIFT_BYTE), hx(LOWSTEP_NIB),
                               " BASE=", hex24(base24), " N=", hex24(n24), 8'h0D, 8'h0A };

    wire [8*29-1:0] rpt_l4 = { "RND=", hex32(rnd_cur), "/", hex32(ROUNDS),
                               " PAT=", hx(pat_mode), 8'h0D, 8'h0A };

    wire [8*33-1:0] rpt_l5 = { "W=",   hex16(wr_i[15:0]),
                               " R=",  hex16(rd_i[15:0]),
                               " CAP=",hex16(cap_cnt[15:0]),
                               " BAD=",hex16(bad_cnt),      8'h0D, 8'h0A };

    wire [8*16-1:0] rpt_l6 = { "TOT=", hex40(tot_cnt), 8'h0D, 8'h0A };

    wire [8*44-1:0] rpt_l7 = { "BAD0=", hex32(rnd_rep), ":", hex24(bad0_rep),
                               " E=",   hex32(exp_rep),
                               " A=",   hex32(act_rep),     8'h0D, 8'h0A };
    wire [8*6-1:0]  rpt_l8 = { "DONE", 8'h0D, 8'h0A };


    reg [8*44-1:0] rpt_line_sel;
    reg [5:0]      rpt_byte_pos;
    always @* begin
        rpt_line_sel = { {(44-6){8'h00}}, rpt_l8 };
        rpt_byte_pos = rpt_idx[5:0];
        if (rpt_idx >= 8'd175) begin
            rpt_line_sel = rpt_l1;
            rpt_byte_pos = rpt_idx - 8'd175;
        end else if (rpt_idx >= 8'd158) begin
            rpt_line_sel = rpt_l2;
            rpt_byte_pos = rpt_idx - 8'd158;
        end else if (rpt_idx >= 8'd128) begin
            rpt_line_sel = rpt_l3;
            rpt_byte_pos = rpt_idx - 8'd128;
        end else if (rpt_idx >= 8'd99) begin
            rpt_line_sel = rpt_l4;
            rpt_byte_pos = rpt_idx - 8'd99;
        end else if (rpt_idx >= 8'd66) begin
            rpt_line_sel = rpt_l5;
            rpt_byte_pos = rpt_idx - 8'd66;
        end else if (rpt_idx >= 8'd50) begin
            rpt_line_sel = rpt_l6;
            rpt_byte_pos = rpt_idx - 8'd50;
        end else if (rpt_idx >= 8'd6) begin
            rpt_line_sel = rpt_l7;
            rpt_byte_pos = rpt_idx - 8'd6;
        end
    end


    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            rpt_line_q     <= {(8*44){1'b0}};
            rpt_byte_pos_q <= 6'd0;
            rpt_line_valid <= 1'b0;
            rpt_byte_q     <= 8'd0;
            rpt_byte_valid <= 1'b0;
        end else if (st != ST_REPORT || !rpt_run) begin
            rpt_line_valid <= 1'b0;
            rpt_byte_valid <= 1'b0;
        end else if (!rpt_byte_valid && !rpt_line_valid && (rpt_idx < RPT_LEN)) begin
            rpt_line_q     <= rpt_line_sel;
            rpt_byte_pos_q <= rpt_byte_pos;
            rpt_line_valid <= 1'b1;
        end else if (!rpt_byte_valid && rpt_line_valid) begin
            rpt_byte_q     <= rpt_line_q[{rpt_byte_pos_q, 3'b000} +: 8];
            rpt_byte_valid <= 1'b1;
            rpt_line_valid <= 1'b0;
        end else if (rpt_byte_valid && uart_tx_ready) begin
            rpt_byte_valid <= 1'b0;
        end
    end

    assign uart_tx_valid = (st == ST_REPORT) && rpt_run && rpt_byte_valid;
    assign uart_tx_data  = rpt_byte_q;


    sdram u_sdram (
        .Clk              (ext_mem_clk),
        .Clk_sft          (ext_mem_clk_sft),
        .Rst              (rst_mem),
        .Sdr_init_done    (sdr_init_done),
        .Sdr_init_ref_vld (sdr_init_ref_vld),
        .Sdr_busy         (sdr_busy),
        .App_wr_en        (app_wr_en),
        .App_wr_addr      (app_wr_addr),
        .App_wr_dm        (app_wr_dm),
        .App_wr_din       (app_wr_din),
        .App_rd_en        (app_rd_en),
        .App_rd_addr      (app_rd_addr),
        .Sdr_rd_en        (sdr_rd_en),
        .Sdr_rd_dout      (sdr_rd_dout)
    );


    uart_tx #(
        .CLK_FREQ (MEM_CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (ext_mem_clk),
        .rst_n     (rst_mem_n),
        .tx_valid  (uart_tx_valid),
        .tx_data   (uart_tx_data),
        .tx_ready  (uart_tx_ready),
        .txd       (uart_txd)
    );

endmodule
