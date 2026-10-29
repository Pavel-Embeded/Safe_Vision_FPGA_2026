


`timescale 1ns / 1ps
`include "pixel_format_defs.vh"

module tb_b_frame_memory;


    reg clk = 1'b0;
    always #4.0 clk = ~clk;
    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
     end endtask

    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W * H;
    localparam integer WORDS_TOTAL = FRAME_PIX/2;


    function [23:0] px24;
        input integer x;
        input integer y;
        reg [7:0] rr,gg,bb;
        begin begin
            rr=x[7:0]^y[7:0]; gg=x+y; bb=x*3;
            px24={rr,gg,bb};
        end
     end endfunction


    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
     end endfunction


    reg [15:0] exp_lo [0:WORDS_TOTAL-1];
    reg [15:0] exp_hi [0:WORDS_TOTAL-1];


    reg [7:0] hdr [0:53];
    initial begin : v_local_1 
        integer i;
        for (i = 0; i < 54; i = i + 1) hdr[i] = 8'h00;
        hdr[0]  = 8'h42; hdr[1]  = 8'h4D;
        hdr[2]  = (54 + FRAME_PIX*3) & 8'hFF;
        hdr[3]  = ((54 + FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[4]  = ((54 + FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[5]  = ((54 + FRAME_PIX*3) >> 24) & 8'hFF;
        hdr[10] = 54;
        hdr[14] = 40;
        hdr[18] = W & 8'hFF;      hdr[19] = (W >> 8) & 8'hFF;
        hdr[22] = H & 8'hFF;      hdr[23] = (H >> 8) & 8'hFF;
        hdr[26] = 1;
        hdr[28] = 24;
        hdr[34] = (FRAME_PIX*3) & 8'hFF;
        hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    reg  [7:0]  bmp_data  = 8'h00;
    reg         bmp_valid = 1'b0;
    wire        bmp_ready;
    reg         bmp_eof   = 1'b0;

    integer bi = 0;
    integer bx = 0, by = 0, bc = 0;
    integer fidx;
    reg [23:0] px_tmp;

    always @(posedge clk) begin
        if (!rst_n) begin
            bi <= 0; bmp_valid <= 1'b0; bmp_eof <= 1'b0;
            bx <= 0; by <= 0; bc <= 0;
        end else begin
            bmp_eof <= 1'b0;
            if (!bmp_valid || bmp_ready) begin
                if (bi < 54) begin
                    bmp_data  <= hdr[bi];
                    bmp_valid <= 1'b1;
                    bi        <= bi + 1;
                end else if (by < H) begin


                    px_tmp    = px24(bx, H - 1 - by);
                    bmp_data  <= (bc == 0)  ?  px_tmp[7:0]  :
                                 (bc == 1)  ?  px_tmp[15:8] :
                                             px_tmp[23:16];
                    bmp_valid <= 1'b1;
                    bi        <= bi + 1;

                    if (bc == 2) begin
                        fidx = (H - 1 - by) * W + bx;
                        if (fidx[0] == 1'b0) exp_lo[fidx >> 1] <= px565(bx, H-1-by);
                        else                 exp_hi[fidx >> 1] <= px565(bx, H-1-by);
                        bc <= 0;
                        if (bx == W-1) begin bx <= 0; by <= by + 1; end
                        else bx <= bx + 1;
                    end else bc <= bc + 1;
                    if ((bx == W-1) && (bc == 2) && (by == H-1)) bmp_eof <= 1'b1;
                end else begin
                    bmp_valid <= 1'b0;
                end
            end
        end
    end


    wire        bp_ready;
    wire        bp_check_done, bp_check_error;
    wire [7:0]  bp_err_code, bp_err_detail;
    wire [15:0] bp_width, bp_height;
    wire        bp_top_down;
    wire [7:0]  bp_bpp;
    wire [31:0] bp_compression, bp_pixel_off, bp_file_size_o;
    wire [7:0]  bp_out_data;
    wire        bp_out_valid, bp_out_sof, bp_out_eof, bp_out_ready;

    bmp_parser u_bmp_parser (
        .clk(clk), .rst_n(rst_n),
        .data(bmp_data), .valid(bmp_valid), .ready(bmp_ready), .eof(bmp_eof),
        .file_size(54 + FRAME_PIX*3),
        .check_done(bp_check_done), .check_error(bp_check_error),
        .err_code(bp_err_code), .err_detail(bp_err_detail),
        .width(bp_width), .height(bp_height), .top_down(bp_top_down),
        .bpp(bp_bpp), .compression(bp_compression), .pixel_off(bp_pixel_off),
        .file_size_o(bp_file_size_o), .dbg_state(),
        .out_data(bp_out_data), .out_valid(bp_out_valid), .out_ready(bp_out_ready),
        .out_sof(bp_out_sof), .out_eof(bp_out_eof)
    );

    wire [15:0] bu_pixel;
    wire        bu_pixel_valid, bu_pixel_ready;
    wire [9:0]  bu_x, bu_y;
    wire        bu_img_sof, bu_img_eof, bu_done, bu_error;
    wire [7:0]  bu_err_code, bu_err_detail;

    bmp_unpack u_bmp_unpack (
        .clk(clk), .rst_n(rst_n),
        .din(bp_out_data), .din_valid(bp_out_valid), .din_ready(bp_out_ready),
        .din_sof(bp_out_sof), .din_eof(bp_out_eof),
        .width(bp_width), .height(bp_height), .top_down(bp_top_down), .pixel_off(bp_pixel_off),
        .pixel(bu_pixel), .pixel_valid(bu_pixel_valid), .pixel_ready(bu_pixel_ready),
        .x(bu_x), .y(bu_y), .img_sof(bu_img_sof), .img_eof(bu_img_eof),
        .done(bu_done), .error(bu_error), .err_code(bu_err_code), .err_detail(bu_err_detail),
        .dbg_state()
    );

    reg         fw_start = 1'b0;
    wire        fw_wr_req, fw_wr_done, fw_crc_ok, fw_wr_error, fw_wr_ready;
    wire [31:0] fw_wr_addr, fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire [7:0]  fw_err_code, fw_err_detail;

    bmp_frame_write_bridge u_frame_writer (
        .top_down(bp_top_down),
        .clk(clk), .rst_n(rst_n),
        .start(fw_start), .slot_sel(2'd1), .slot_base(`SV_IMG1_BASE),
        .din(bu_pixel), .din_valid(bu_pixel_valid), .din_ready(bu_pixel_ready),
        .wr_req(fw_wr_req), .wr_addr(fw_wr_addr), .wr_data(fw_wr_data), .wr_len(fw_wr_len),
        .wr_ready(fw_wr_ready), .wr_done(fw_wr_done),
        .slot_valid(fw_slot_valid), .crc_ok(fw_crc_ok), .crc_value(fw_crc_value),
        .px_cnt(fw_px_cnt), .wr_error(fw_wr_error),
        .err_code(fw_err_code), .err_detail(fw_err_detail)
    );


    reg         arb_rd_req = 1'b0;
    reg  [31:0] arb_rd_addr = 32'd0;
    wire [15:0] arb_rd_len = 16'd64;
    wire        arb_rd_ack, arb_rd_busy, arb_rd_data_valid;
    wire [31:0] arb_rd_data;
    wire        arb_wr_ack, arb_wr_busy;
    wire        mem_req, mem_wr;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg         mem_ready = 1'b1;
    reg  [31:0] mem_rdata = 32'd0;
    reg         mem_rdata_valid = 1'b0;

    assign fw_wr_ready = arb_wr_ack;

    memory_arbiter #(.MAX_BURSTS(4), .STARVE_LIMIT(64)) u_arb (
        .clk(clk), .rst_n(rst_n), .video_fifo_level(16'd32),
        .rd_req(arb_rd_req), .rd_addr(arb_rd_addr), .rd_len(arb_rd_len),
        .rd_ack(arb_rd_ack), .rd_busy(arb_rd_busy),
        .rd_data(arb_rd_data), .rd_data_valid(arb_rd_data_valid),
        .wr_req(fw_wr_req), .wr_addr(fw_wr_addr), .wr_data(fw_wr_data), .wr_len(fw_wr_len),
        .wr_ack(arb_wr_ack), .wr_busy(arb_wr_busy),
        .sd_req(1'b0), .sd_wr(1'b0), .sd_addr(32'd0), .sd_wdata(32'd0), .sd_len(16'd0),
        .sd_ack(), .sd_busy(), .sd_rdata(), .sd_rdata_valid(),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_rdata_valid(mem_rdata_valid),
        .wr_starve_cnt(), .rd_starve_cnt()
    );

    localparam integer MEM_WORDS = 512 * 1024;
    reg [31:0] sd_mem [0:MEM_WORDS-1];

    integer mcyc = 0;
    always @(posedge clk) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 17) != 0);
    end

    reg [31:0] raddr_p0, raddr_p1, raddr_p2;
    reg [2:0]  rv_pipe;
    always @(posedge clk) begin
        if (!rst_n) begin
            raddr_p0 <= 0; raddr_p1 <= 0; raddr_p2 <= 0;
            rv_pipe <= 3'd0; mem_rdata_valid <= 1'b0; mem_rdata <= 32'd0;
        end else begin
            raddr_p0 <= mem_addr;
            raddr_p1 <= raddr_p0;
            raddr_p2 <= raddr_p1;
            rv_pipe  <= { rv_pipe[1:0], (mem_req && mem_ready && !mem_wr) };
            mem_rdata_valid <= rv_pipe[2];
            if (rv_pipe[2]) mem_rdata <= sd_mem[raddr_p2[20:2]];
            if (mem_req && mem_ready && mem_wr) sd_mem[mem_addr[20:2]] <= mem_wdata;
        end
    end


    localparam integer RD_BURST = 64;
    localparam integer N_BURST  = WORDS_TOTAL / RD_BURST;

    reg         rd_start = 1'b0;
    integer     bst = 0;
    integer     wcnt = 0;
    integer     widx = 0;
    integer     wok = 0, wbad = 0;
    integer     ack_multi = 0, v_wo_busy = 0, ack_cnt = 0, v_cnt = 0;
    reg         ack_d = 1'b0;

    always @(posedge clk) begin
        ack_d <= arb_rd_ack;
        if (!rst_n) begin
            arb_rd_req <= 1'b0; arb_rd_addr <= 32'd0;
            bst <= 0; wcnt <= 0;
        end else begin

            if (arb_rd_ack && ack_d)     ack_multi = ack_multi + 1;
            if (arb_rd_ack)              ack_cnt   = ack_cnt + 1;
            if (arb_rd_data_valid && !arb_rd_busy) v_wo_busy = v_wo_busy + 1;
            if (arb_rd_data_valid)       v_cnt     = v_cnt + 1;


            if (arb_rd_data_valid) begin
                if (arb_rd_data === { exp_hi[widx], exp_lo[widx] }) wok = wok + 1;
                else begin
                    wbad = wbad + 1;
                    if (wbad <= 3)
                        $display("[INFO] word mismatch: burst=%0d idx=%0d got=%h want=%h",
                                 bst-1, widx, arb_rd_data, { exp_hi[widx], exp_lo[widx] });
                end
                widx = widx + 1;
                wcnt = wcnt + 1;
                if (wcnt == RD_BURST) wcnt = 0;
            end


            if (!rd_start) begin
                arb_rd_req <= 1'b0;
            end else if (bst < N_BURST) begin
                if (!arb_rd_req && !arb_rd_busy) begin
                    arb_rd_req  <= 1'b1;
                    arb_rd_addr <= `SV_IMG1_BASE + bst * RD_BURST * 4;
                end else if (arb_rd_ack) begin
                    arb_rd_req <= 1'b0;
                    bst <= bst + 1;
                end
            end else begin
                arb_rd_req <= 1'b0;
            end
        end
    end


    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;


        repeat (4) @(posedge clk);
        @(negedge clk); fw_start = 1'b1;
        @(negedge clk); fw_start = 1'b0;


        wait (bu_done || bu_error || (fw_px_cnt == `SV_FRAME_PIXELS));
        check(!bu_error,                 "1) bmp_unpack 无错（BMP 头与像素段都被接受）");
        check(!bp_check_error,           "2) BMP 头校验通过");
        check(bp_width  == 16'd640,      "3) 解析出宽度 = 640");
        check(bp_height == 16'd480,      "4) 解析出高度 = 480");


        wait (fw_slot_valid[1] || fw_wr_error);
        check(!fw_wr_error,                    "5) frame_writer 写帧无错");
        check(fw_px_cnt == `SV_FRAME_PIXELS,   "6) frame_writer 写满 307200 像素");
        check(fw_crc_ok == 1'b1,               "7) frame_writer CRC 校验通过");
        check(fw_slot_valid[1] == 1'b1,        "8) 槽 1 slot_valid 置位（A 才允许读）");


        rd_start = 1'b1;
        wait (bst >= N_BURST);
        wait (v_cnt >= WORDS_TOTAL);
        repeat (100) @(posedge clk);
        rd_start = 1'b0;

        check(wbad == 0,                 "9) ★ 帧缓存 153600 个 word **逐字与 BMP 像素对一致**（0 错）");
        check(wok  == WORDS_TOTAL,       "10) 比对字数 = 153600（不多不少）");
        check(ack_cnt == N_BURST,        "11) 读突发数 = 2400（每个突发一次 ack）");
        check(ack_multi == 0,            "12) rd_ack 单拍（无连续两拍）");
        check(v_wo_busy == 0,            "13) rd_data_valid 只在 rd_busy 期间出现");
        check(v_cnt == WORDS_TOTAL,      "14) 读回字数 = 153600");

        $display("[TB] tb_b_frame_memory done, errors=%0d (wok=%0d wbad=%0d bursts=%0d vcnt=%0d)",
                 errors, wok, wbad, ack_cnt, v_cnt);
        $finish;
    end


    initial begin
        forever begin
            #2_000_000;
            $display("[PROG] t=%0t bi=%0d bu_done=%b fw_px=%0d fw_done=%b slotv=%b bst=%0d vcnt=%0d wok=%0d wbad=%0d",
                     $time, bi, bu_done, fw_px_cnt, fw_wr_done, fw_slot_valid, bst, v_cnt, wok, wbad);
        end
    end


    initial begin
        #200_000_000;
        $display("[FAIL] tb_b_frame_memory 看门狗超时（bi=%0d fw_px=%0d bst=%0d vcnt=%0d wok=%0d wbad=%0d）",
                 bi, fw_px_cnt, bst, v_cnt, wok, wbad);
        $finish;
    end

endmodule
