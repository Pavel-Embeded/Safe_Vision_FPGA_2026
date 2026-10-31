


`timescale 1ns / 1ps

module tb_common_fifo;


    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors   = 0;
    integer pass_cnt = 0;
    integer i, k;

    reg [15:0] tmp16;

    task check;
        input         cond;
        input [511:0] name;
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s", name);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end

     end endtask


    reg  [7:0] sk_in_data;
    reg        sk_in_valid;
    wire       sk_in_ready;
    wire [7:0] sk_out_data;
    wire       sk_out_valid;
    reg        sk_out_ready;

    reg  [7:0] sk_cap [0:15];
    integer    sk_n;
    reg        sk_mon_en;
    integer    sk_ov_cnt;

    rv_skid_buffer #(.W(8)) u_skid (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_data  (sk_in_data),
        .in_valid (sk_in_valid),
        .in_ready (sk_in_ready),
        .out_data (sk_out_data),
        .out_valid(sk_out_valid),
        .out_ready(sk_out_ready)
    );

    always @(posedge clk) begin
        if (sk_out_valid && sk_out_ready) begin
            sk_cap[sk_n] = sk_out_data;
            sk_n = sk_n + 1;
        end
        if (sk_mon_en && sk_out_valid) begin
            sk_ov_cnt = sk_ov_cnt + 1;
        end
    end


    reg  [15:0] f_din;
    reg         f_wr;
    wire        f_full, f_afull, f_empty, f_aempty;
    wire [15:0] f_dout;
    wire [6:0]  f_cnt;
    reg         f_rd;

    sync_fifo #(
        .W               (16),
        .DEPTH           (64),
        .ALMOST_FULL_TH  (48),
        .ALMOST_EMPTY_TH (4)
    ) u_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (f_wr),
        .din         (f_din),
        .full        (f_full),
        .almost_full (f_afull),
        .rd_en       (f_rd),
        .dout        (f_dout),
        .empty       (f_empty),
        .almost_empty(f_aempty),
        .data_count  (f_cnt)
    );

    wire [15:0] fh_min, fh_uf, fh_of, fh_cur;
    reg         fh_clr;

    fifo_health_monitor u_fh (
        .clk          (clk),
        .rst_n        (rst_n),
        .clr          (fh_clr),
        .data_count   ({9'b0, f_cnt}),
        .empty        (f_empty),
        .full         (f_full),
        .rd_en        (f_rd),
        .wr_en        (f_wr),
        .min_level    (fh_min),
        .underflow_cnt(fh_uf),
        .overflow_cnt (fh_of),
        .cur_level    (fh_cur)
    );

    reg [15:0] exp  [0:63];
    reg [15:0] b6_dat[0:63];
    integer    mism;
    integer    wx, rx;


    task fifo_push1;
        input [15:0] d;
        begin
            f_din = d;
            f_wr  = 1'b1;
            @(negedge clk);
            f_wr  = 1'b0;

     end endtask


    task fifo_pop1;
        output [15:0] d;
        begin
            d    = f_dout;
            f_rd = 1'b1;
            @(negedge clk);
            f_rd = 1'b0;

     end endtask


    task fifo_push_wait;
        input [15:0] d;
        begin
            while (f_afull) @(negedge clk);
            f_din = d;
            f_wr  = 1'b1;
            @(negedge clk);
            f_wr  = 1'b0;

     end endtask


    task fifo_pop_wait;
        output [15:0] d;
        begin
            while (f_empty) @(negedge clk);
            d    = f_dout;
            f_rd = 1'b1;
            @(negedge clk);
            f_rd = 1'b0;

     end endtask


    reg  [15:0] m_lvl;
    reg         m_empty, m_full, m_rd, m_wr, m_clr;
    wire [15:0] m_min, m_uf, m_of, m_cur;

    fifo_health_monitor u_fh2 (
        .clk          (clk),
        .rst_n        (rst_n),
        .clr          (m_clr),
        .data_count   (m_lvl),
        .empty        (m_empty),
        .full         (m_full),
        .rd_en        (m_rd),
        .wr_en        (m_wr),
        .min_level    (m_min),
        .underflow_cnt(m_uf),
        .overflow_cnt (m_of),
        .cur_level    (m_cur)
    );


    reg  [31:0] bw_wrb, bw_rdb;
    reg         bw_wrv, bw_rdv;
    reg  [31:0] bw_win;
    wire [31:0] bw_rdtot, bw_wrtot, bw_rdmb, bw_wrmb;
    wire        bw_done;

    memory_bandwidth_monitor #(.CLK_MHZ(125)) u_bw (
        .clk           (clk),
        .rst_n         (rst_n),
        .wr_bytes      (bw_wrb),
        .wr_valid      (bw_wrv),
        .rd_bytes      (bw_rdb),
        .rd_valid      (bw_rdv),
        .window_cycles (bw_win),
        .rd_bytes_total(bw_rdtot),
        .wr_bytes_total(bw_wrtot),
        .rd_bw_mbps    (bw_rdmb),
        .wr_bw_mbps    (bw_wrmb),
        .window_done   (bw_done)
    );


    reg         er_push;
    reg  [7:0]  er_code;
    reg  [3:0]  er_src;
    reg  [31:0] er_ts;
    wire [3:0]  er_type;
    wire [15:0] er_value;
    wire        er_valid, er_full;
    wire [15:0] er_drop;

    error_report u_er (
        .clk       (clk),
        .rst_n     (rst_n),
        .err_push  (er_push),
        .err_code  (er_code),
        .err_src   (er_src),
        .err_ts    (er_ts),
        .evt_type  (er_type),
        .evt_value (er_value),
        .evt_valid (er_valid),
        .evt_full  (er_full),
        .drop_cnt  (er_drop)
    );

    task er_push1;
        input [7:0]  c;
        input [3:0]  s;
        input [31:0] t;
        begin
            @(negedge clk);
            er_push = 1'b1;
            er_code = c;
            er_src  = s;
            er_ts   = t;
            @(negedge clk);
            er_push = 1'b0;

     end endtask


    initial begin

        sk_in_valid = 0; sk_in_data = 0; sk_out_ready = 0;
        sk_n = 0; sk_mon_en = 0; sk_ov_cnt = 0;
        f_wr = 0; f_din = 0; f_rd = 0; fh_clr = 0;
        m_lvl = 0; m_empty = 1; m_full = 0; m_rd = 0; m_wr = 0; m_clr = 0;
        bw_wrb = 0; bw_rdb = 0; bw_wrv = 0; bw_rdv = 0; bw_win = 32'd1000;
        er_push = 0; er_code = 0; er_src = 0; er_ts = 0;
        mism = 0;

        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);


        sk_mon_en = 0; sk_n = 0; sk_ov_cnt = 0;
        sk_in_valid = 1'b1; sk_in_data = 8'h11; sk_out_ready = 1'b0;
        @(negedge clk);
        check(sk_out_valid && (sk_out_data == 8'h11),
              "skid-A1: 首字节进入输出寄存器");

        sk_in_data = 8'h22;
        @(negedge clk);
        check(sk_out_valid && (sk_out_data == 8'h11),
              "skid-A1: 下游反压第 1 拍 out_data 保持");
        @(negedge clk);
        check(sk_out_valid && (sk_out_data == 8'h11),
              "skid-A1: 下游反压第 2 拍 out_data 保持");
        check(sk_in_ready == 1'b0,
              "skid-A1: 溢出寄存器占用时 in_ready=0（切分点成立）");

        sk_out_ready = 1'b1; sk_in_valid = 1'b0;
        repeat (3) @(negedge clk);
        check(sk_n == 2, "skid-A1: 反压期间被压住的 2 个字节全部取出");
        check((sk_cap[0] == 8'h11) && (sk_cap[1] == 8'h22),
              "skid-A1: 取出顺序正确 0x11 -> 0x22");
        check(sk_out_valid == 1'b0, "skid-A1: 排空后 out_valid 归零");


        sk_out_ready = 1'b0;
        repeat (2) @(negedge clk);
        sk_n = 0; sk_ov_cnt = 0; sk_mon_en = 1'b1;
        sk_in_valid = 1'b1; sk_in_data = 8'h30; sk_out_ready = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            sk_in_data = 8'h30 + i + 1;
            if (i == 7) sk_in_valid = 1'b0;
        end
        @(negedge clk);
        sk_mon_en = 0;
        check(sk_n == 8, "skid-A2: 连续 8 拍输入全部输出（不丢字节）");
        check(sk_ov_cnt == 8, "skid-A2: 连续 8 拍 out_valid 无气泡");
        check((sk_cap[0] == 8'h30) && (sk_cap[1] == 8'h31) &&
              (sk_cap[2] == 8'h32) && (sk_cap[3] == 8'h33) &&
              (sk_cap[4] == 8'h34) && (sk_cap[5] == 8'h35) &&
              (sk_cap[6] == 8'h36) && (sk_cap[7] == 8'h37),
              "skid-A2: 连续输出顺序 0x30..0x37 正确");
        sk_out_ready = 1'b0;


        check(f_empty && (f_cnt == 7'd0),
              "fifo-B1: 复位后 empty=1、data_count=0");
        for (i = 0; i < 10; i = i + 1) fifo_push1(16'h0100 + i);
        @(negedge clk);
        check(f_cnt == 7'd10, "fifo-B1: 写 10 个后 data_count=10");
        check(!f_empty && !f_aempty,
              "fifo-B1: 写 10 个后 empty=0 且高于 almost_empty 阈值");
        for (i = 0; i < 3; i = i + 1) fifo_pop1(tmp16);
        @(negedge clk);
        check(f_cnt == 7'd7, "fifo-B1: 读 3 个后 data_count=7");


        for (i = 0; i < 40; i = i + 1) fifo_push1(16'h0200 + i);
        @(negedge clk);
        check(f_cnt == 7'd47, "fifo-B2: 写到 47 时 data_count=47");
        check(f_afull == 1'b0, "fifo-B2: 47 < 阈值 48，almost_full=0");
        fifo_push1(16'hFFFF);
        @(negedge clk);
        check((f_cnt == 7'd48) && f_afull,
              "fifo-B2: 到达阈值 48 时 almost_full 拉高");


        for (i = 0; i < 16; i = i + 1) fifo_push1(16'h0300 + i);
        @(negedge clk);
        check((f_cnt == 7'd64) && f_full,
              "fifo-B3: 写满 64 时 full=1，data_count 能取到 DEPTH 本身");

        @(negedge clk);
        f_din = 16'hDEAD; f_wr = 1'b1;
        repeat (4) @(negedge clk);
        f_wr = 1'b0;
        @(negedge clk);
        check((f_cnt == 7'd64) && f_full,
              "fifo-B3: 满时继续写，data_count 仍为 64（写指针不溢出）");
        check(fh_of == 16'd4,
              "fifo-B3: 满时写 4 次 -> overflow_cnt=4");


        k = 0;
        for (i = 3; i < 10; i = i + 1) begin exp[k] = 16'h0100 + i; k = k + 1; end
        for (i = 0; i < 40; i = i + 1) begin exp[k] = 16'h0200 + i; k = k + 1; end
        exp[k] = 16'hFFFF; k = k + 1;
        for (i = 0; i < 16; i = i + 1) begin exp[k] = 16'h0300 + i; k = k + 1; end
        check(k == 64, "fifo-B4: 期望序列长度 = 64");

        mism = 0;
        for (i = 0; i < 64; i = i + 1) begin
            fifo_pop1(tmp16);
            if (tmp16 !== exp[i]) mism = mism + 1;
        end
        @(negedge clk);
        check(mism == 0, "fifo-B4: 读出的 64 个字节与写入顺序完全一致");
        check(f_empty && (f_cnt == 7'd0), "fifo-B4: 排空后 empty=1、data_count=0");
        check(fh_min == 16'd0, "fifo-B4: 见底后 min_level=0（历史最低水位正确）");


        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            f_rd = 1'b1;
            @(negedge clk);
            f_rd = 1'b0;
        end
        @(negedge clk);
        check(f_empty && (f_cnt == 7'd0),
              "fifo-B4: 空时读 4 次，empty / data_count 不变（不产生假数据）");
        check(fh_uf == 16'd4,
              "fifo-B4: 空时读 4 次 -> underflow_cnt=4");
        fifo_push1(16'h7777);
        @(negedge clk);
        check(f_cnt == 7'd1, "fifo-B4: 空读之后写 1 个 -> data_count=1");
        fifo_pop1(tmp16);
        @(negedge clk);
        check(tmp16 == 16'h7777,
              "fifo-B4: 空读之后写入的字节能被正确读出（指针未被偷走）");
        check(f_empty && (f_cnt == 7'd0), "fifo-B4: 再读一次后重新为空");


        f_wr = 1'b0; f_rd = 1'b0; f_din = 16'd0; fh_clr = 1'b0;
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        check(f_empty && (f_cnt == 7'd0), "fifo-B6: 重新复位后为空");
        check((fh_of == 16'd0) && (fh_uf == 16'd0),
              "fifo-B6: 重现复位后 underflow / overflow 计数归零");

        f_rd = 1'b0;
        fork
            begin

                for (wx = 0; wx < 64; wx = wx + 1) fifo_push_wait(16'h2000 + wx);
            end
            begin

                repeat (100) @(negedge clk);
                for (rx = 0; rx < 64; rx = rx + 1) fifo_pop_wait(b6_dat[rx]);
            end
        join
        @(negedge clk);

        check(fh_of == 16'd0,
              "fifo-B6: 读侧停 100 拍期间 overflow_cnt = 0");
        check(fh_uf == 16'd0,
              "fifo-B6: 全程读空/写满均未发生 -> underflow_cnt = 0");
        check(fh_min >= 16'd0, "fifo-B6: min_level 有统计值");
        mism = 0;
        for (i = 0; i < 64; i = i + 1) begin
            if (b6_dat[i] !== (16'h2000 + i)) mism = mism + 1;
        end
        check(mism == 0,
              "fifo-B6: 停 100 拍期间写入的 64 个字节全部按序读出（不丢数据）");
        check(f_empty && (f_cnt == 7'd0), "fifo-B6: 收工后 FIFO 为空");


        m_lvl = 16'd0; m_empty = 1'b1; m_full = 1'b0;
        m_rd = 1'b0; m_wr = 1'b0; m_clr = 1'b0;
        @(negedge clk); m_clr = 1'b1;
        @(negedge clk); m_clr = 1'b0; m_lvl = 16'd10;
        @(negedge clk);
        check(m_min == 16'd10, "monitor-C: clr 后第一拍即记录 10（不是被 0 锁死）");
        @(negedge clk); m_lvl = 16'd5;
        @(negedge clk);
        check(m_min == 16'd5, "monitor-C: 更低水位被记录为 min_level");
        @(negedge clk); m_lvl = 16'd20;
        @(negedge clk); @(negedge clk); m_lvl = 16'd8;
        @(negedge clk);
        check(m_min == 16'd5, "monitor-C: 更高水位不改变 min_level");
        check(m_cur == 16'd8, "monitor-C: cur_level 跟随 data_count");

        m_lvl = 16'd0; m_empty = 1'b1; m_full = 1'b0;
        m_rd = 1'b1;
        repeat (3) @(negedge clk);
        m_rd = 1'b0;
        @(negedge clk);
        check(m_uf == 16'd3, "monitor-C: 空时读 3 次 -> underflow_cnt=3");

        m_empty = 1'b0; m_full = 1'b1; m_wr = 1'b1;
        repeat (5) @(negedge clk);
        m_wr = 1'b0; m_full = 1'b0;
        @(negedge clk);
        check(m_of == 16'd5, "monitor-C: 满时写 5 次 -> overflow_cnt=5");


        bw_win = 32'd1000; bw_wrb = 32'd2; bw_rdb = 32'd4;


        bw_wrv = 1'b1; bw_rdv = 1'b1;
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        @(posedge bw_done);
        #1;
        check(bw_rdmb == 32'd500,
              "bw-D: 4 B/拍 @125MHz -> rd_bw = 500 MB/s（与手算一致）");
        check(bw_wrmb == 32'd250,
              "bw-D: 2 B/拍 @125MHz -> wr_bw = 250 MB/s（与手算一致）");
        check(bw_rdtot == 32'd4000, "bw-D: 一个窗口读出 4000 Byte");
        check(bw_wrtot == 32'd2000, "bw-D: 一个窗口写入 2000 Byte");
        @(posedge clk);
        @(negedge clk);
        check(bw_done == 1'b0, "bw-D: window_done 是单拍脉冲");

        @(posedge bw_done);
        #1;
        check(bw_rdtot == 32'd8000, "bw-D: 第二个窗口后累计读出 8000 Byte");
        check(bw_rdmb == 32'd500, "bw-D: 第二个窗口带宽保持一致");
        bw_wrv = 1'b0; bw_rdv = 1'b0;


        er_push = 1'b0; er_code = 8'd0; er_src = 4'd0; er_ts = 32'd0;
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        check(!er_valid && !er_full && (er_drop == 16'd0),
              "error-E: 复位后 evt_valid=0、evt_full=0、drop_cnt=0");

        for (i = 0; i < 8; i = i + 1) begin
            er_push1(i[7:0] + 8'h30, i[3:0], 32'd1000 + i);
        end
        @(negedge clk);
        check(er_valid, "error-E: 压入 8 条后 evt_valid=1");
        check(er_full, "error-E: 8 条占满深度 8 -> evt_full=1");
        check(er_drop == 16'd0, "error-E: 恰好 8 条时 drop_cnt=0");

        er_push1(8'h38, 4'h8, 32'd1008);
        er_push1(8'h39, 4'h9, 32'd1009);
        @(negedge clk);
        check(er_drop == 16'd2, "error-E: 满后再压 2 条 -> drop_cnt=2");
        check(er_full, "error-E: 溢出时 evt_full 保持为 1");
        check(er_type == 4'h0,
              "error-E: 队首 evt_type = 首条 err_src（已存事件未被覆盖）");
        check(er_value == 16'h0030,
              "error-E: 队首 evt_value = 首条 err_code（已存事件未被覆盖）");
        check(er_valid, "error-E: 队列非空，evt_valid 仍为 1");


        $display("--------------------------------------------------");
        $display("[SUMMARY] tb_common_fifo : PASS=%0d FAIL=%0d", pass_cnt, errors);
        if (errors == 0) $display("[RESULT] ALL PASS");
        else             $display("[RESULT] FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

endmodule
