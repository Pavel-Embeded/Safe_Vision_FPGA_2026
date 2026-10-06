// Actual B BMP parser/unpacker/writer + A stages1-20 assembly.
// Models only the downstream memory, not the physical SDRAM or HDMI encoder.
`timescale 1ns / 1ps
`include "pixel_format_defs.vh"

module tb_a_video_system_core #(parameter integer HD=0, MUTATE_COLOR=0, SUBMIT_LEAD=0, SWAPS=1, IMMEDIATE=0);

    // ------------------------------------------------------------------------
    // 三个时钟域（与整机一致：sys 100M / mem 125M / pixel 74.25M）
    // ------------------------------------------------------------------------
    reg clk_sys = 1'b0;  always #5.0   clk_sys = ~clk_sys;
    reg clk_mem = 1'b0;  always #4.0   clk_mem = ~clk_mem;
    reg clk_pix = 1'b0;  always #(HD ? 6.734 : 19.861) clk_pix = ~clk_pix;

    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input string name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W * H;

    // ========================================================================
    // 1) BMP 字节源：54 Byte 头 + 640×480×24bit 像素（自底向上存，BMP 常规）
    //    像素值 = px24(x,y) 的确定性函数，显示侧用同一个函数算期望值。
    // ========================================================================
    function [23:0] px24;
        input integer x;
        input integer y;
        reg [7:0] rr,gg,bb;
        begin
            // BGR 存盘；这里给的是 RGB 语义值
            rr=x[7:0]^y[7:0]; gg=x+y; bb=x*3;
            px24={rr,gg,bb};
        end
    endfunction

    // RGB565（与 bmp_unpack 的截断口径一致：R>>3, G>>2, B>>3）
    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    // RGB888（把 RGB565 展开成 888，与 A 的 core 的 expand 口径一致）
    function [23:0] expand565;
        input [15:0] p;
        begin
            expand565 = { p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2] };
        end
    endfunction

    reg [7:0] hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) hdr[i] = 8'h00;
        hdr[0]  = 8'h42; hdr[1]  = 8'h4D;                       // "BM"
        hdr[2]  = (54 + FRAME_PIX*3) & 8'hFF;                  // 文件大小（小端）
        hdr[3]  = ((54 + FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[4]  = ((54 + FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[5]  = ((54 + FRAME_PIX*3) >> 24) & 8'hFF;
        hdr[10] = 54;                                          // bfOffBits = 54
        hdr[14] = 40;                                          // biSize = 40
        hdr[18] = W & 8'hFF;      hdr[19] = (W >> 8) & 8'hFF;   // biWidth
        hdr[22] = H & 8'hFF;      hdr[23] = (H >> 8) & 8'hFF;   // biHeight（正 = 自底向上）
        hdr[26] = 1;                                           // biPlanes
        hdr[28] = 24;                                          // biBitCount
        hdr[34] = (FRAME_PIX*3) & 8'hFF;                       // biSizeImage
        hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    // 字节流：先 54 个头字节，再按 BMP 行序（自底向上）输出 B,G,R
    reg  [7:0]  bmp_data  = 8'h00;
    reg         bmp_valid = 1'b0;
    wire        bmp_ready;
    reg         bmp_eof   = 1'b0;

    integer bi = 0;                     // 已发出的字节序号
    integer bx, by, bc;                 // 当前像素坐标与通道
    reg [23:0] px_tmp;         // ★ 先把函数返回值存下来再选位（Questa vopt 会对 f(x)[7:0] 崩）
    integer row_pad;
    always @(posedge clk_mem) begin
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
                    // BMP 自底向上：第 0 行 = 图像最后一行
                    px_tmp    = px24(bx, H-1-by);
                    bmp_data  <= (bc == 0) ? px_tmp[7:0]    :   // B
                                 (bc == 1) ? px_tmp[15:8]   :   // G
                                             px_tmp[23:16];     // R
                    bmp_valid <= 1'b1;
                    bi        <= bi + 1;
                    if (bc == 2) begin
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

    // ========================================================================
    // 2) B：bmp_parser → bmp_unpack → frame_writer
    // ========================================================================
    wire        bp_ready;
    wire        bp_check_done, bp_check_error;
    wire [7:0]  bp_err_code, bp_err_detail;
    wire [15:0] bp_width, bp_height;
    wire        bp_top_down;
    wire [7:0]  bp_bpp;
    wire [31:0] bp_compression, bp_pixel_off, bp_file_size_o;
    wire [7:0]  bp_out_data;
    wire        bp_out_valid, bp_out_sof, bp_out_eof;
    wire        bp_out_ready;

    bmp_parser u_bmp_parser (
        .clk        (clk_mem),
        .rst_n      (rst_n),
        .data       (bmp_data),
        .valid      (bmp_valid),
        .ready      (bmp_ready),
        .eof        (bmp_eof),
        .file_size  (54 + FRAME_PIX*3),
        .check_done (bp_check_done),
        .check_error(bp_check_error),
        .err_code   (bp_err_code),
        .err_detail (bp_err_detail),
        .width      (bp_width),
        .height     (bp_height),
        .top_down   (bp_top_down),
        .bpp        (bp_bpp),
        .compression(bp_compression),
        .pixel_off  (bp_pixel_off),
        .file_size_o(bp_file_size_o),
        .dbg_state  (),
        .out_data   (bp_out_data),
        .out_valid  (bp_out_valid),
        .out_ready  (bp_out_ready),
        .out_sof    (bp_out_sof),
        .out_eof    (bp_out_eof)
    );

    wire [15:0] bu_pixel;
    wire        bu_pixel_valid, bu_pixel_ready;
    wire [9:0]  bu_x, bu_y;
    wire        bu_img_sof, bu_img_eof;
    wire        bu_done, bu_error;
    wire [7:0]  bu_err_code, bu_err_detail;

    bmp_unpack u_bmp_unpack (
        .clk         (clk_mem),
        .rst_n       (rst_n),
        .din         (bp_out_data),
        .din_valid   (bp_out_valid),
        .din_ready   (bp_out_ready),
        .din_sof     (bp_out_sof),
        .din_eof     (bp_out_eof),
        .width       (bp_width),
        .height      (bp_height),
        .top_down    (bp_top_down),
        .pixel_off   (bp_pixel_off),
        .pixel       (bu_pixel),
        .pixel_valid (bu_pixel_valid),
        .pixel_ready (bu_pixel_ready),
        .x           (bu_x),
        .y           (bu_y),
        .img_sof     (bu_img_sof),
        .img_eof     (bu_img_eof),
        .done        (bu_done),
        .error       (bu_error),
        .err_code    (bu_err_code),
        .err_detail  (bu_err_detail),
        .dbg_state   ()
    );

    reg         fw_start = 1'b0;
    wire [1:0]  fw_slot_sel = 2'd1;                       // 写到 IMG1 槽
    wire [31:0] fw_slot_base = `SV_IMG1_BASE;
    wire        fw_wr_req, fw_wr_done, fw_crc_ok, fw_wr_error;
    wire [31:0] fw_wr_addr, fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire [7:0]  fw_err_code, fw_err_detail;
    wire        fw_wr_ready;

    bmp_frame_write_bridge u_frame_writer (
        .top_down(bp_top_down),
        .clk        (clk_mem),
        .rst_n      (rst_n),
        .start      (fw_start),
        .slot_sel   (fw_slot_sel),
        .slot_base  (fw_slot_base),
        .din        (bu_pixel),
        .din_valid  (bu_pixel_valid),
        .din_ready  (bu_pixel_ready),
        .wr_req     (fw_wr_req),
        .wr_addr    (fw_wr_addr),
        .wr_data    (fw_wr_data),
        .wr_len     (fw_wr_len),
        .wr_ready   (fw_wr_ready),
        .wr_done    (fw_wr_done),
        .slot_valid (fw_slot_valid),
        .crc_ok     (fw_crc_ok),
        .crc_value  (fw_crc_value),
        .px_cnt     (fw_px_cnt),
        .wr_error   (fw_wr_error),
        .err_code   (fw_err_code),
        .err_detail (fw_err_detail)
    );

    // ========================================================================
    // 3) B：memory_arbiter（写通道接 frame_writer，读通道接 A 的 core）
    // ========================================================================
    wire        arb_rd_req;
    wire [31:0] arb_rd_addr;
    wire [15:0] arb_rd_len;
    wire        arb_rd_ack, arb_rd_busy, arb_rd_data_valid;
    wire [31:0] arb_rd_data;
    wire        arb_wr_ack, arb_wr_busy;

    wire        mem_req, mem_wr;
    reg         mem_ready = 1'b1;      // 本 TB 驱动（存储模型）
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata = 32'd0;     // 本 TB 驱动
    reg         mem_rdata_valid = 1'b0;// 本 TB 驱动

    wire [15:0] pix_fifo_level;

    // frame_writer 的 wr_ready = 仲裁器受理了这一拍（本模块逐 word 请求、len=1）
    assign fw_wr_ready = arb_wr_ack;


    // ---- 存储模型：真存真取（模拟 mem_ctrl 的下游）----
    localparam integer MEM_WORDS = 1024 * 1024;              // 4 MiB
    reg [31:0] sd_mem [0:MEM_WORDS-1];

    integer mcyc = 0;
    always @(posedge clk_mem) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 17) != 0);                     // 周期性忙，制造真实竞争
    end

    reg [31:0] raddr_p0, raddr_p1, raddr_p2;
    reg [2:0]  rv_pipe;
    always @(posedge clk_mem) begin
        if (!rst_n) begin
            raddr_p0 <= 0; raddr_p1 <= 0; raddr_p2 <= 0;
            rv_pipe <= 3'd0; mem_rdata_valid <= 1'b0; mem_rdata <= 32'd0;
        end else begin
            raddr_p0 <= mem_addr;
            raddr_p1 <= raddr_p0;
            raddr_p2 <= raddr_p1;
            rv_pipe  <= { rv_pipe[1:0], (mem_req && mem_ready && !mem_wr) };
            mem_rdata_valid <= rv_pipe[2];
            if (rv_pipe[2]) mem_rdata <= sd_mem[raddr_p2[21:2]];
            if (mem_req && mem_ready && mem_wr) sd_mem[mem_addr[21:2]] <= mem_wdata;
        end
    end

    // ========================================================================
    // 4) B：frame_swap_ctrl + frame_swap_cdc（换帧握手，让 A 知道显示哪个槽）
    // ========================================================================
    reg         frame_ready = 1'b0;
    reg [7:0] submitted_generation=8'hfe;reg submitted_fi=0;
    integer swap_i;
    wire        swap_req_b, mb_fidx_b, mb_crc_b, swap_error, active_commit;
    wire [2:0]  swap_state_o;      // 诊断：帧交换 FSM 当前状态
    wire [1:0]  mb_slot_b, active_next;
    wire [7:0]  mb_gen_b, gen_next;
    wire        fs_evt_b, ack_evt_b;

    // ★ 超时要用能覆盖一整帧的值：A 的 core 在真实垂直消隐才回 frame_start，
    //   一帧约 16.7 ms。早先这里给了 40000 拍（=400 us）⇒ 等不到消隐就超时进 SAFE。
    //   模块默认 5_000_000 拍（=50 ms）正是覆盖一整帧加余量，直接用默认值。

    assign swap_req_b=u_display.video.swap_req_b;
    wire req_evt_a, frame_start_a, swap_ack_a;
    // ★★ 这里**故意不再例化 `frame_swap_cdc`**：A 的 `a_video_display_core` 内部
    //    已经有一个（`swaps` 实例），它把 A 侧的 `frame_start`/`swap_ack` 变成
    //    B 域单拍事件，从 core 的 `frame_start_evt_b`/`swap_ack_evt_b` 输出。
    //    ⇒ 整机里 B 侧**不应该**再放一份 CDC。
    //    ★ 本 TB 早先版本违反了这条（又例化了一个 u_cdc 驱动同一组线），
    //      造成 `fs_evt_b`/`ack_evt_b` **双驱动**，换帧 FSM 永远收不到 frame_start、
    //      超时进 SAFE —— 曾一度被误判成 RTL bug，实际是 TB 接线错。


    // A 侧（pixel 域）行为模型：收到请求 → 给 frame_start 单拍 → toggle swap_ack
    // ---- ★ 脉冲捕获（必须用 always 数边沿；1 ms 采样看不到单周期事件）----
    //   ★ 只观察 **TB 级**信号：层次引用在 vopt 下不可靠（而且 TB 里已不再例化 CDC，
    //     A 的 core 内部那个 CDC 的输入输出就是下面这两根线）。
    integer fs_b_pulses = 0, ack_b_pulses = 0;
    reg     fs_b_d = 1'b0, ack_b_d = 1'b0;
    always @(posedge clk_sys) begin
        fs_b_d  <= fs_evt_b;
        ack_b_d <= ack_evt_b;
        if (fs_evt_b  && !fs_b_d)  fs_b_pulses  = fs_b_pulses  + 1;
        if (ack_evt_b && !ack_b_d) ack_b_pulses = ack_b_pulses + 1;
    end

    // ★ 计数器必须声明在使用它的 always 块之前（否则 Verilog 建隐式网线、报 undefined）
    integer a_req_seen = 0, a_acks = 0, commits = 0;
    reg     cmt_d = 1'b0;
    // ★★ 独立诊断：数 FSM 状态转移序列 + 用**另一个**计数器数 active_commit 边沿
    integer acmt_edges = 0, st_changes = 0;
    reg     acmt_d = 1'b0;
    reg [2:0] st_d = 3'd0;
    always @(posedge clk_sys) begin
        if (!rst_n) begin acmt_d <= 1'b0; st_d <= 3'd0; end
        else begin
            acmt_d <= active_commit;
            if (active_commit && !acmt_d) acmt_edges = acmt_edges + 1;
            st_d <= swap_state_o;
            if (swap_state_o !== st_d) begin
                st_changes = st_changes + 1;
                $display("[FSM] t=%0t state %0d -> %0d  active_commit=%b", $time, st_d, swap_state_o, active_commit);
            end
        end
    end

    // ★ 换帧提交计数（之前只声明了变量、增量块跟 A 模型一起被删了 ⇒ 恒 0）
    always @(posedge clk_sys) begin
        if (!rst_n) cmt_d <= 1'b0;
        else begin
            cmt_d <= active_commit;
            if (active_commit && !cmt_d) commits = commits + 1;
        end
    end
    // ★ A 侧的应答（frame_start / swap_ack）现在由 **A 的 core 内部**产生，
    //   TB 不再模拟 A 的应答（早先版本自己模拟了一份，同时 core 也有一份 ⇒ 双驱动）。
    //   因此 `a_req_seen` / `a_acks` 这两个 TB 侧计数不再可用（core 内部不可见）。

    // ========================================================================
    // 5) A：a_video_display_core（阶段 11–15）
    // ========================================================================
    wire [11:0] scan_x, scan_y;
    wire        scan_de, scan_frame_start;
    wire [23:0] disp_rgb;
    wire [11:0] disp_x, disp_y;
    wire        disp_hs, disp_vs, disp_de, disp_pixel_valid, disp_line_start;
    wire        disp_frame_start, disp_afs, disp_hblank, disp_vblank;
    wire [1:0]  disp_layer, pix_active_slot;
    wire [7:0]  pix_generation;
    wire        pix_active_valid, pix_frame_fault;
    wire [31:0] pix_underflow, pix_missed, mem_overflow;
    wire        mem_dma_active, mem_dma_done;
    wire [2:0]  mem_fetch_state;
    wire [31:0] mem_dma_bytes;

    reg ctrl_valid=0,ctrl_active=0;wire ctrl_ready,em_active,em_applied,em_pending;
    wire [63:0] pixel_debug,mem_debug;wire [31:0] sys_debug;
    integer applied_count=0,em_pixels=0,normal_before=0;
    reg [7:0] glyph[0:4095];
    initial $readmemh("font8x16.mem",glyph);
    function [23:0] emergency_expected(input integer xx,yy);
        integer cx,cy,dy,tx,ty,idx,ch;reg arrow_hit,border_hit,font_hit;
        begin
            cx=HD?640:320;cy=HD?360:240;tx=cx-16;ty=HD?180:120;
            dy=(yy>=cy)?yy-cy:cy-yy;
            arrow_hit=(xx>=cx-96&&xx<=cx-32&&dy<=((xx-cx+96)/2))||
                (xx>=cx+32&&xx<=cx+96&&dy<=((cx+96-xx)/2))||
                (xx>=cx-32&&xx<=cx+32&&dy<=12);
            border_hit=xx<4||xx>=(HD?1276:636)||yy<4||yy>=(HD?716:476);
            font_hit=0;
            if(xx>=tx&&xx<tx+32&&yy>=ty&&yy<ty+16)begin
                idx=(xx-tx)/8;
                case(idx)0:ch=69;1:ch=88;2:ch=73;default:ch=84;endcase
                font_hit=glyph[ch*16+yy-ty][7-((xx-tx)%8)];
            end
            emergency_expected=(arrow_hit||border_hit||font_hit)?24'h00ff00:24'h001008;
        end
    endfunction
    task control(input bit level);
        begin
            @(negedge clk_sys);ctrl_active=level;ctrl_valid=1;
            do @(posedge clk_sys);while(!ctrl_ready);
            @(negedge clk_sys);ctrl_valid=0;
            wait(em_active==level);
        end
    endtask
    always @(posedge clk_pix) if(rst_n&&em_applied)applied_count=applied_count+1;
    // Probes must reflect the immediately preceding edge in THEIR own domain.
    // Verify actual field positions instead of assuming a trace is useful.
    reg [63:0] want_pixel_debug,want_mem_debug;reg [31:0] want_sys_debug;
    integer debug_checks=0;
    always @(posedge clk_pix)begin
        want_pixel_debug=u_display.prn?{em_active,u_display.emergency_pixel_level,
            u_display.emergency_pixel_direction,em_applied,pix_generation,pix_active_slot,
            pix_active_valid,pix_frame_fault,disp_de,disp_pixel_valid,disp_hs,disp_vs,
            disp_x,disp_y,disp_layer,pix_underflow[7:0],pix_missed[7:0]}:64'd0;
        #0.001;
        if(pixel_debug!==want_pixel_debug)$fatal(1,"PIXEL debug edge/field alignment");
        if(rst_n)debug_checks=debug_checks+1;
    end
    always @(posedge clk_mem)begin
        want_mem_debug=u_display.mrn?{mem_fetch_state,mem_dma_active,mem_dma_done,
            pix_fifo_level,mem_dma_bytes,arb_wr_busy,u_display.rd_starve_cnt[9:0]}:64'd0;
        #0.001;
        if(mem_debug!==want_mem_debug)$fatal(1,"MEM debug edge/field alignment");
    end
    always @(posedge clk_sys)begin
        want_sys_debug=u_display.srn?{8'd0,submitted_generation,2'd1,submitted_fi,
            fw_crc_ok,frame_ready,ctrl_valid,ctrl_ready,1'b0,u_display.cfg_ready,
            swap_state_o,swap_error,active_commit,fs_evt_b,ack_evt_b}:32'd0;
        #0.001;
        if(sys_debug!==want_sys_debug)$fatal(1,"SYS debug edge/field alignment");
    end

    a_video_system_core #(
        .HD      (HD), .EMERGENCY_IMMEDIATE(IMMEDIATE),
        .FIFO_AW (10),
        .BURST_WORDS (64),
        .FONT_FILE ("font8x16.mem")
    ) u_display (
        .sys_clk    (clk_sys),
        .mem_clk    (clk_mem),
        .pixel_clk  (clk_pix),
        .rst_n      (rst_n),
        .frame_ready(frame_ready),.wr_frame_index(submitted_fi),.wr_slot_id(2'd1),
        .wr_generation(submitted_generation),.wr_crc_ok(fw_crc_ok),
        .active_commit(active_commit),.active_next(active_next),.generation_next(gen_next),
        .frame_index_next(),.swap_error(swap_error),.swap_state_o(swap_state_o),
        .frame_start_evt_b(fs_evt_b),.swap_ack_evt_b(ack_evt_b),
        .wr_req(fw_wr_req),.wr_addr(fw_wr_addr),.wr_data(fw_wr_data),.wr_len(fw_wr_len),
        .wr_ack(arb_wr_ack),.wr_busy(arb_wr_busy),
        .sd_req(1'b0),.sd_wr(1'b0),.sd_addr(32'd0),.sd_wdata(32'd0),.sd_len(16'd0),
        .sd_ack(),.sd_busy(),.sd_rdata(),.sd_rdata_valid(),
        .mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),
        .mem_rdata_valid(mem_rdata_valid),.wr_starve_cnt(),.rd_starve_cnt(),
        .cfg_valid  (1'b0),
        .cfg_ready  (),
        .cfg_osd_enable (1'b0),
        .cfg_mode   (2'b00),
        .cfg_fps_tens (4'd6),
        .cfg_fps_ones (4'd0),
        .cfg_sd_ok  (1'b1),
        .cfg_origin_x (12'd0),
        .cfg_origin_y (12'd0),
        .cfg_foreground (24'hFFFFFF),
        .emergency_ctrl_valid(ctrl_valid),.emergency_ctrl_ready(ctrl_ready),
        .emergency_active(ctrl_active),.direction(2'd2),.warning_level(2'd0),
        .emergency_pixel_active(em_active),.emergency_pixel_direction(),.emergency_pixel_level(),
        .emergency_applied(em_applied),.emergency_pending(em_pending),
        .pixel_debug(pixel_debug),.mem_debug(mem_debug),.sys_debug(sys_debug),
        .scan_x     (scan_x),
        .scan_y     (scan_y),
        .scan_de    (scan_de),
        .scan_frame_start (scan_frame_start),
        .rgb        (disp_rgb),
        .x          (disp_x),
        .y          (disp_y),
        .hsync      (disp_hs),
        .vsync      (disp_vs),
        .de         (disp_de),
        .pixel_valid(disp_pixel_valid),
        .line_start (disp_line_start),
        .frame_start(disp_frame_start),
        .active_frame_start (disp_afs),
        .hblank     (disp_hblank),
        .vblank     (disp_vblank),
        .selected_layer (disp_layer),
        .pix_active_slot (pix_active_slot),
        .pix_generation  (pix_generation),
        .pix_frame_index (),
        .pix_active_valid(pix_active_valid),
        .pix_frame_fault (pix_frame_fault),
        .pix_underflow_count (pix_underflow),
        .pix_missed_frame_count (pix_missed),
        .mem_overflow_count (mem_overflow),
        .mem_fifo_pixels (pix_fifo_level),
        .mem_dma_bytes  (mem_dma_bytes),
        .mem_dma_active (mem_dma_active),
        .mem_dma_done   (mem_dma_done),
        .mem_fetch_state(mem_fetch_state)
    );

    // ========================================================================
    // 6) 断言：屏幕像素 == 源 BMP 像素
    //    A 的 core 内部有固定的图层延迟（Normal=1 / OSD=4 / Emergency=0，最终 5 拍），
    //    所以按"延迟 5 拍对齐"比较（与 A 的 TB 同口径）。
    // ========================================================================
    integer pix_ok = 0, pix_bad = 0;
    integer red_samples=0,green_samples=0,blue_samples=0;
    integer frame_no = 0;
    reg [23:0] exp_rgb [0:4];
    integer    ei;
    reg        comparing = 1'b0;

    always @(posedge clk_pix) begin
        if (!rst_n) begin
            comparing <= 1'b0;
            for (ei = 0; ei < 5; ei = ei + 1) exp_rgb[ei] = 24'h000000;
        end else begin
            // ★ 直接比对，**不要给期望值加延迟**：A 的 core 输出的 `x`/`y` 本身就已经是
            //   延迟后的扫描坐标（`rgb` 与 `x`/`y`/`de` 在输出端本来就同拍）。
            //   早先版本把期望值再延迟 5 拍，等于拿 x-5 的期望去比 x 的像素 ——
            //   表现是"每个像素都错、且错得像横向平移 5 个像素"（实测踩过）。
            if (pix_active_valid) comparing <= 1'b1;

            if (comparing && disp_de && disp_layer==1 && (disp_x >= (HD?320:0)) && (disp_x < (HD?960:W)) && (disp_y >= (HD?120:0)) && (disp_y < (HD?600:H))) begin
                if(disp_rgb[23:16]!=0)red_samples=red_samples+1;
                if(disp_rgb[15:8]!=0)green_samples=green_samples+1;
                if(disp_rgb[7:0]!=0)blue_samples=blue_samples+1;
                if ((disp_rgb[23:0] ^ (MUTATE_COLOR ? 24'h010000 : 24'h000000)) === expand565(px565(disp_x-(HD?320:0), disp_y-(HD?120:0)))) pix_ok = pix_ok + 1;
                else begin
                    pix_bad = pix_bad + 1;
                    if (pix_bad <= 3)
                        $display("[INFO] pixel mismatch @(%0d,%0d) got=%h want=%h",
                                 disp_x, disp_y, disp_rgb[23:0],
                                 expand565(px565(disp_x-(HD?320:0), disp_y-(HD?120:0))));
                end
            end
            if(comparing&&disp_de&&disp_layer==3)begin
                em_pixels=em_pixels+1;
                if(disp_rgb!==emergency_expected(disp_x,disp_y))begin
                    pix_bad=pix_bad+1;
                    if(pix_bad<4)$display("[FAIL] Emergency RGB @%0d,%0d got=%h expected=%h",
                        disp_x,disp_y,disp_rgb,emergency_expected(disp_x,disp_y));
                end
            end
            if (disp_frame_start) frame_no = frame_no + 1;
        end
    end

    time a_commit_time=0,b_commit_time=0;
    integer commit_phase_errors=0;
    always @(posedge clk_pix) if(rst_n && u_display.video.display.slot.pending && u_display.scan_frame_start) begin
        a_commit_time=$time;
        $display("[PHASE] A frame-boundary commit t=%0t",$time);
    end
    always @(pix_generation or posedge pix_active_valid) if(rst_n && pix_active_valid) begin
        if($time!=a_commit_time)commit_phase_errors=commit_phase_errors+1;
    end
    always @(posedge active_commit) begin
        b_commit_time=$time;
        $display("[PHASE] B commit t=%0t delta=%0t",$time,$time-a_commit_time);
    end
    initial if($test$plusargs("WAVES")) begin
        $dumpfile("swap.vcd");
        $dumpvars(0,frame_ready,swap_req_b,fs_evt_b,ack_evt_b,active_commit,
          swap_state_o,pix_active_valid,pix_active_slot,pix_generation,scan_frame_start);
        $dumpvars(0,ctrl_valid,ctrl_ready,ctrl_active,em_active,em_applied,em_pending);
    end
    // Bounded memory waveform in CSV: one actual 64-word read burst plus its
    // final busy release. Avoid dumping every 125MHz clock for whole frames.
    integer debug_fd=0,debug_rows=0;
    initial if($test$plusargs("WAVES"))begin
        debug_fd=$fopen("emergency_pixels.csv","w");
        if(!debug_fd)$fatal(1,"debug capture open");
        $fdisplay(debug_fd,"t_ns,x,y,de,layer,rgb,pixel_debug");
    end
    always @(negedge clk_pix)if(debug_fd!=0&&disp_de&&disp_layer==3)begin
        $fdisplay(debug_fd,"%0d,%0d,%0d,%0b,%0d,%06h,%016h",$time,disp_x,disp_y,
            disp_de,disp_layer,disp_rgb,pixel_debug);
        debug_rows=debug_rows+1;
        if(debug_rows==256)begin $fclose(debug_fd);debug_fd=0;end
    end
    integer burst_fd=0,burst_words=0;
    reg capture_burst=0;
    initial if($test$plusargs("WAVES"))begin
        burst_fd=$fopen("read_burst.csv","w");
        if(!burst_fd)$fatal(1,"cannot create burst capture");
        $fdisplay(burst_fd,"t_ns,req,ack,busy,addr,len,valid,data");
    end
    always @(posedge clk_mem)if(rst_n && burst_fd!=0)begin
        if(u_display.video.rd_ack)capture_burst=1;
        if(capture_burst)begin
            $fdisplay(burst_fd,"%0d,%0b,%0b,%0b,%08h,%0d,%0b,%08h",$time,
              u_display.video.rd_req,u_display.video.rd_ack,u_display.video.rd_busy,
              u_display.video.rd_addr,u_display.video.rd_len,u_display.video.rd_data_valid,u_display.video.rd_data);
            if(burst_words==64)begin $fclose(burst_fd);burst_fd=0;end
            else if(u_display.video.rd_data_valid)burst_words=burst_words+1;
        end
    end
    // ========================================================================
    // 7) 主流程
    // ========================================================================
    initial begin
        rst_n = 1'b0;
        #400;
        rst_n = 1'b1;

        // ★ 必须先启动 frame_writer：它的 din_ready 要求 running
        repeat (4) @(posedge clk_mem);
        @(negedge clk_mem); fw_start = 1'b1;
        @(negedge clk_mem); fw_start = 1'b0;

        // 等 BMP 字节流发完
        wait (bu_done || bu_error || (fw_px_cnt == `SV_FRAME_PIXELS));
        check(!bu_error, "1) bmp_unpack 无错（BMP 头与像素段都被接受）");
        check(bp_width  == 16'd640, "2) bmp_parser 解析出宽度 = 640");
        check(bp_height == 16'd480, "3) bmp_parser 解析出高度 = 480");
        check(!bp_check_error,      "4) BMP 头校验通过");

        // 等 frame_writer 写完
        wait (fw_slot_valid[1] || fw_wr_error);
        check(!fw_wr_error, "5) frame_writer 写帧无错");
        check(fw_px_cnt == `SV_FRAME_PIXELS, "6) frame_writer 写满 307200 像素");
        check(fw_crc_ok == 1'b1, "7) frame_writer CRC 校验通过");
        check(fw_slot_valid[1] == 1'b1, "8) 槽 1 的 slot_valid 置位（A 才允许读）");

        if(SUBMIT_LEAD>0)wait(scan_y==(HD?719:479) && scan_x==(HD?1650:800)-SUBMIT_LEAD);
        // 触发换帧握手
        @(negedge clk_sys);
        frame_ready = 1'b1;
        @(negedge clk_sys);
        frame_ready = 1'b0;

        // ★ 等**电平**信号 pix_active_valid，不要等单拍信号 active_commit：
        //   后者是 sys 域单拍，若在 wait 之前就闪过，wait 会永久挂住（实测踩过）。
        wait (pix_active_valid);
        // ★ 比对窗口：从“画面已激活”开始，再跨两整帧
        //   （早先只等 2000 拍，落在消隐期 ⇒ pix_ok=0）
        repeat (2) @(posedge disp_frame_start);
        repeat (2000) @(posedge clk_pix);

        // 等两帧画面，然后收账
        wait (frame_no >= 2);
        repeat (2000) @(posedge clk_pix);

        // Repeated requests exercise opposite mailbox/ACK ordering and 8-bit
        // generation wrap FE->FF->00->01; payload changes only in B IDLE.
        for(swap_i=1;swap_i<SWAPS;swap_i=swap_i+1)begin
            wait(swap_state_o==0);
            wait(scan_y==(HD?719:479) && scan_x==(HD?1650:800)-(swap_i%4+1));
            @(negedge clk_sys);submitted_generation=submitted_generation+1'b1;
            submitted_fi=~submitted_fi;frame_ready=1;
            @(negedge clk_sys);frame_ready=0;
            wait(pix_generation==submitted_generation);
            wait(swap_state_o==0);
            @(posedge disp_frame_start);repeat(2000)@(posedge clk_pix);
        end
        normal_before=pix_ok;
        control(1);
        wait(em_pixels>=(HD?1280*720:640*480));
        control(0);
        wait(pix_ok>=normal_before+FRAME_PIX);
        repeat(20)@(posedge clk_pix);
        check(applied_count==2&&!em_pending,"one apply for each C emergency request");
        check(em_pixels>=(HD?1280*720:640*480),"full Emergency raster matched");
        $display("[SYSTEM] HD=%0d IMMEDIATE=%0d normal=%0d emergency=%0d applied=%0d",
            HD,IMMEDIATE,pix_ok,em_pixels,applied_count);
        check(pix_generation==submitted_generation,"submitted generation matches active generation");
        check(commit_phase_errors == 0, "A commits only at a raw frame boundary");
        check(b_commit_time >= a_commit_time && (b_commit_time-a_commit_time) < 100,
              "B commit follows A within 100ns, not a whole frame");
        check(ack_b_pulses == SWAPS && commits == SWAPS, "one request has one ACK and one B commit");
        check(px24(255,0)==24'hFFFFFD && px24(0,255)==24'hFFFF00,
              "independent red/green/blue color anchors");
        check(red_samples>0 && green_samples>0 && blue_samples>0,"all color channels exercised");
        check(swap_error == 1'b0, "9) 换帧握手无超时");
        check(commits >= 1, "9b) 换帧确实提交了（active_commit 至少 1 次）");
        check(pix_ok >= FRAME_PIX, "10) 显示侧至少比对上 200000 个像素（画面真的出来了）");
        check(pix_bad == 0,    "11) ★ 显示像素与源 BMP 像素**逐点一致**（0 个不符）");
        check(pix_underflow == 0, "12) 无像素欠流（A 的 underflow 计数 = 0）");
        check(mem_overflow == 0,  "13) 无 FIFO 溢出");
        check(pix_frame_fault == 0, "14) 无帧故障标记");

        $display("[TB] tb_a_video_system_core done, errors=%0d (pix_ok=%0d pix_bad=%0d frames=%0d commits=%0d swapst=%0d swap_err=%b fsB=%0d ackB=%0d acmt=%0d stchg=%0d)",
                 errors, pix_ok, pix_bad, frame_no, commits, swap_state_o, swap_error,
                 fs_b_pulses, ack_b_pulses, acmt_edges, st_changes);
        $finish;
    end

    // ---- 换帧过程诊断（每 1 ms 打一行，只在 frame_ready 之后开始，避免刷屏）----
    reg diag_on = 1'b0;
    always @(posedge clk_sys) if (frame_ready) diag_on <= 1'b1;
    initial begin
        forever begin
            #1_000_000;
            if (diag_on)
                $display("[SWAP] t=%0t st=%0d req=%b fs_b=%b ack_b=%b reqa=%b commits=%0d err=%b | fsB=%0d ackB=%0d",
                         $time, swap_state_o, swap_req_b, fs_evt_b, ack_evt_b, req_evt_a,
                         commits, swap_error,
                         fs_b_pulses, ack_b_pulses);
        end
    end

    // 看门狗（本 TB 要过 92 万字节 + 两帧扫描，给足）
    initial begin
        #200_000_000;
        $display("[FAIL] tb_a_video_system_core 看门狗超时（bi=%0d fw_px=%0d frames=%0d ok=%0d bad=%0d active=%b swapst=%0d swap_err=%b commits=%0d）",
                 bi, fw_px_cnt, frame_no, pix_ok, pix_bad, pix_active_valid, swap_state_o, swap_error, commits);
        $finish;
    end

    // 进度（每 2 ms 仿真时间打一行，便于定位慢在哪一段）
    initial begin
        forever begin
            #2_000_000;
            $display("[PROG] t=%0t bi=%0d bu_done=%b fw_px=%0d fw_done=%b slotv=%b active=%b frames=%0d ok=%0d bad=%0d",
                     $time, bi, bu_done, fw_px_cnt, fw_wr_done, fw_slot_valid,
                     pix_active_valid, frame_no, pix_ok, pix_bad);
        end
    end

endmodule
