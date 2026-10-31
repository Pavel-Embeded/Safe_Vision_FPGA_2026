


`timescale 1ns / 1ps

module tb_bram_adapter_aligned;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #4 clk = ~clk;

    integer errors = 0;
    integer total  = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            total = total + 1;
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end

     end endtask


    reg         rq = 1'b0, rw = 1'b0;
    reg  [31:0] ra = 32'd0, rwd = 32'd0;
    reg  [3:0]  rstrb = 4'hF;
    wire [31:0] rd;
    wire        rvl, rdy, idn;


    wire        app_wr_en;
    wire [20:0] app_wr_addr;
    wire [3:0]  app_wr_dm;
    wire [31:0] app_wr_din;
    wire        app_rd_en;
    wire [20:0] app_rd_addr;

    reg         sdr_rd_en   = 1'b0;
    reg  [31:0] sdr_rd_dout = 32'd0;


    reg         sdr_init_done = 1'b0;

    sdram_app_adapter u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .req               (rq),
        .wr                (rw),
        .addr              (ra),
        .wdata             (rwd),
        .wstrb             (rstrb),
        .rdata             (rd),
        .rdata_valid       (rvl),
        .ready             (rdy),
        .init_done         (idn),
        .Sdr_init_done     (sdr_init_done),
        .Sdr_init_ref_vld  (1'b0),
        .Sdr_busy          (1'b0),
        .App_wr_en         (app_wr_en),
        .App_wr_addr       (app_wr_addr),
        .App_wr_dm         (app_wr_dm),
        .App_wr_din        (app_wr_din),
        .App_rd_en         (app_rd_en),
        .App_rd_addr       (app_rd_addr),
        .Sdr_rd_en         (sdr_rd_en),
        .Sdr_rd_dout       (sdr_rd_dout)
    );


    integer    init_cnt      = 0;

    localparam integer MEMW   = 1 << 16;
    localparam integer RD_LAT = 4;

    reg [31:0] mem [0:MEMW-1];

    always @(posedge clk) if (init_cnt < 100) init_cnt <= init_cnt + 1;
    always @(posedge clk) if (init_cnt >= 100) sdr_init_done <= 1'b1;


    always @(posedge clk) begin
        if (app_wr_en) begin
            if (!app_wr_dm[0]) mem[app_wr_addr][7:0]   <= app_wr_din[7:0];
            if (!app_wr_dm[1]) mem[app_wr_addr][15:8]  <= app_wr_din[15:8];
            if (!app_wr_dm[2]) mem[app_wr_addr][23:16] <= app_wr_din[23:16];
            if (!app_wr_dm[3]) mem[app_wr_addr][31:24] <= app_wr_din[31:24];
        end
    end


    reg [20:0] pl_a [0:RD_LAT];
    reg        pl_v [0:RD_LAT];
    integer    i;

    always @(posedge clk) begin
        sdr_rd_en   <= 1'b0;
        if (pl_v[RD_LAT]) begin
            sdr_rd_en   <= 1'b1;
            sdr_rd_dout <= mem[pl_a[RD_LAT]];
        end
        for (i = RD_LAT; i > 0; i = i - 1) begin
            pl_a[i] <= pl_a[i-1];
            pl_v[i] <= pl_v[i-1];
        end
        pl_a[0] <= app_rd_addr;
        pl_v[0] <= app_rd_en;
    end


    integer    wr_burst = 0, rd_burst = 0;
    reg [20:0] wr_prev = 21'd0, rd_prev = 21'd0;
    integer    wr_step_bad = 0, rd_step_bad = 0;
    integer    wr_beats = 0, rd_beats = 0;
    integer    rd_gap_min = 9999, rd_gap = 0;
    reg        rd_seen = 1'b0;

    always @(posedge clk) begin

        if (app_wr_en) begin
            if (wr_burst > 0) begin
                if (app_wr_addr !== (wr_prev + 21'd1)) wr_step_bad <= wr_step_bad + 1;
            end
            wr_prev  <= app_wr_addr;
            wr_burst <= wr_burst + 1;
            wr_beats <= wr_beats + 1;
        end else begin
            wr_burst <= 0;
        end


        if (app_rd_en) begin
            if (rd_burst > 0) begin
                if (app_rd_addr !== (rd_prev + 21'd1)) rd_step_bad <= rd_step_bad + 1;
            end
            rd_prev  <= app_rd_addr;
            rd_burst <= rd_burst + 1;
            rd_beats <= rd_beats + 1;
            if (rd_seen && (rd_gap < rd_gap_min)) rd_gap_min <= rd_gap;
            rd_gap   <= 0;
            rd_seen  <= 1'b1;
        end else begin
            rd_burst <= 0;
            rd_gap   <= rd_gap + 1;
        end
    end


    integer to_rdy = 0;
    integer to_rvl = 0;

    task wr_word;
        input [31:0] a;
        input [31:0] d;
        integer g;
        begin
            @(negedge clk);
            rq <= 1'b1; rw <= 1'b1; ra <= a; rwd <= d; rstrb <= 4'hF;
            g = 0;
            @(posedge clk);
            while ((rdy !== 1'b1) && (g < 5000)) begin @(posedge clk); g = g + 1; end
            if (g >= 5000) to_rdy = to_rdy + 1;
            rq <= 1'b0;
            @(negedge clk);

     end endtask

    task rd_word;
        input  [31:0] a;
        output [31:0] d;
        integer g;
        begin
            @(negedge clk);
            rq <= 1'b1; rw <= 1'b0; ra <= a;
            g = 0;
            @(posedge clk);
            while ((rdy !== 1'b1) && (g < 5000)) begin @(posedge clk); g = g + 1; end
            if (g >= 5000) to_rdy = to_rdy + 1;
            rq <= 1'b0;
            g = 0;
            while ((rvl !== 1'b1) && (g < 5000)) begin @(negedge clk); g = g + 1; end
            if (g >= 5000) to_rvl = to_rvl + 1;
            d = rd;
            @(negedge clk);

     end endtask


    reg  [31:0] v;
    integer     k;
    integer     mism16 = 0, mism32 = 0, mism4 = 0, mism_jump = 0;
    reg  [31:0] rbuf [0:31];

    initial begin
        for (k = 0; k < MEMW; k = k + 1) mem[k] = 32'hDEAD_BEEF;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        while (!idn) @(negedge clk);
        repeat (5) @(negedge clk);


        for (k = 0; k < 32; k = k + 1) wr_word(32'h1000 + k, 32'h1000 + k);
        repeat (80) @(negedge clk);


        for (k = 0; k < 32; k = k + 1) begin
            rd_word(32'h1000 + k, v);
            rbuf[k] = v;
            if (v !== (32'h1000 + k)) mism32 = mism32 + 1;
        end
        for (k = 0; k < 16; k = k + 1) if (rbuf[k] !== (32'h1000 + k)) mism16 = mism16 + 1;


        for (k = 0; k < 4; k = k + 1) wr_word(32'h1035 + k, 32'h1035 + k);
        repeat (200) @(negedge clk);
        for (k = 0; k < 4; k = k + 1) begin
            rd_word(32'h1035 + k, v);
            if (v !== (32'h1035 + k)) mism4 = mism4 + 1;
        end


        for (k = 0; k < 4; k = k + 1) begin
            rd_word(32'h1000 + k, v);
            if (v !== (32'h1000 + k)) mism_jump = mism_jump + 1;
        end
        for (k = 0; k < 4; k = k + 1) begin
            rd_word(32'h1035 + k, v);
            if (v !== (32'h1035 + k)) mism_jump = mism_jump + 1;
        end

        repeat (10) @(negedge clk);

        $display("---- 适配器结果 ----");
        $display("  写拍数=%0d 写地址不连续次数=%0d", wr_beats, wr_step_bad);
        $display("  读拍数=%0d 读地址不连续次数=%0d 两次读突发最小静默=%0d 拍",
                 rd_beats, rd_step_bad, rd_gap_min);
        $display("  16 字错=%0d / 32 字错=%0d / 非对齐 4 字错=%0d / 跳变 8 字错=%0d",
                 mism16, mism32, mism4, mism_jump);
        $display("  等 ready 超时=%0d 次 / 等 rdata_valid 超时=%0d 次", to_rdy, to_rvl);

        check(idn === 1'b1,                                   "D1 init_done 上抬");
        check((wr_beats >= 32) && (wr_step_bad == 0),         "D2 写突发地址每拍 +1");
        check(mism16 == 0,                                    "D3 写 32 连续字、前 16 字落对地址");
        check((rd_beats >= 32) && (rd_step_bad == 0),         "D4 读突发地址每拍 +1");
        check((mism32 == 0) && (to_rdy == 0) && (to_rvl == 0),
                                                              "D5 读 32 连续字（跨两次预取）逐字相等");
        check(mism4 == 0,                                     "D6 非 16 对齐基址写 4 读 4 正确");
        check((mism_jump == 0) && (to_rdy == 0) && (to_rvl == 0),
                                                              "D7 缓冲未排空时跳变地址不死等、数据正确");

        $display("========================================");
        $display("  断言总数 %0d，失败 %0d", total, errors);
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("========================================");
        $display("[TB] tb_bram_adapter_aligned done errors=%0d comparisons=%0d",errors,total);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
