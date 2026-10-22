// ============================================================================
// tb_sdr_pat_gen.sv — SDRAM 测试图案生成器（sdr_pat_gen）单元验证
// ----------------------------------------------------------------------------
// 过关标准（自定，2026-10-04；动机见 sdr_pat_gen.v 头注）：
//   T1  稀疏扫描（a = k*2049，k = 0..1023，**mode 0**）：1024 个图案**两两不同**（单射）
//   T2  连续扫描（a = 0..1023，mode 0）：1024 个图案**两两不同**
//   T3  稀疏扫描时 4 个字节**各自**都取到 >= 2 个不同值（32 根 DQ 都在动）
//   T4  21 位地址里**每一位**单独翻转都改变图案（没有"死位"）
//   T5  mode 0 的已知值钉死（防止公式被误改）
//   T6  地址 0 的图案非 0（mode 0 / 1 / 2；避免"全 0 地址写全 0 数据"这种退化）
//   T7  **反向对照**：旧公式（只用了 a[11:4] / a[7:0]）在稀疏扫描下只有 2 种图案
//       —— 证明 T1 的判据确实抓得到那个 bug（测试的测试）
//   T8  **mode 1（LFSR）也是单射**：稀疏扫描 1024 点两两不同（xorshift32 是双射）
//   T9  **mode 2/3/4/5 的已知值钉死**（walking-1 / walking-0 / 全0全1 / 相邻位交替）
//
// ★★ 本 TB 为什么不可省：写侧与读侧用的是**同一个** sdr_pat_gen，所以"图案没有
//    区分度"这类错误在板上会表现为 **BAD=0000 通过**（两边错得一样，自比看不出来）。
//    只有这里能守住这条性质 —— 这正是本项目"仿真全绿连'RTL 与 TB 对约定理解一致'
//    都证明不了"那条教训的正面用法：把**性质**单独拿出来验，而不是只验自比。
// ============================================================================
`timescale 1ns / 1ps

module tb_sdr_pat_gen;

    reg  [20:0] addr;
    reg  [2:0]  mode;
    wire [31:0] pat;

    sdr_pat_gen u_dut ( .addr(addr), .mode(mode), .pat(pat) );

    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // 取一个地址 + 模式下的图案（纯组合，等 1 个时间单位）
    task get_pat;
        input  [20:0] a;
        input  [2:0]  m;
        output [31:0] p;
        begin addr = a; mode = m; #1; p = pat; end
    endtask

    reg [31:0] sp [0:1023];         // 稀疏扫描图案（mode 0）
    reg [31:0] cn [0:1023];         // 连续扫描图案（mode 0）
    reg [31:0] lf [0:1023];         // 稀疏扫描图案（mode 1）
    reg [31:0] old [0:1023];        // 反向对照：旧公式的图案
    reg [20:0] a_old;
    integer cnt_old, hit;
    integer i, j, k;
    integer dup_sp, dup_cn, dup_lf;
    integer v0, v1, v2, v3;
    integer flips_bad;
    reg [31:0] p_base, p_flip;
    reg seen0 [0:255], seen1 [0:255], seen2 [0:255], seen3 [0:255];

    initial begin
        addr = 21'd0;
        mode = 3'd0;

        // ---- 采集三组图案 ----
        for (k = 0; k < 1024; k = k + 1) begin
            get_pat((k * 2049) & 21'h1FFFFF, 3'd0, sp[k]);   // 全片稀疏扫描（步长 2049）
            get_pat(k,                        3'd0, cn[k]);   // 连续
            get_pat((k * 2049) & 21'h1FFFFF, 3'd1, lf[k]);   // 稀疏扫描 + LFSR 模式
        end

        // ---- T1 稀疏扫描（mode 0）：两两不同 ----
        dup_sp = 0;
        for (i = 0; i < 1024; i = i + 1)
            for (j = i + 1; j < 1024; j = j + 1)
                if (sp[i] === sp[j]) dup_sp = dup_sp + 1;
        check(dup_sp == 0, "T1 稀疏扫描（mode 0）1024 个图案两两不同（单射）");

        // ---- T2 连续扫描（mode 0）：两两不同 ----
        dup_cn = 0;
        for (i = 0; i < 1024; i = i + 1)
            for (j = i + 1; j < 1024; j = j + 1)
                if (cn[i] === cn[j]) dup_cn = dup_cn + 1;
        check(dup_cn == 0, "T2 连续扫描（mode 0）1024 个图案两两不同");

        // ---- T3 稀疏扫描时 4 个字节各自都在变 ----
        for (i = 0; i < 256; i = i + 1) begin
            seen0[i] = 1'b0; seen1[i] = 1'b0; seen2[i] = 1'b0; seen3[i] = 1'b0;
        end
        for (i = 0; i < 1024; i = i + 1) begin
            seen0[sp[i][7:0]]   = 1'b1;
            seen1[sp[i][15:8]]  = 1'b1;
            seen2[sp[i][23:16]] = 1'b1;
            seen3[sp[i][31:24]] = 1'b1;
        end
        v0 = 0; v1 = 0; v2 = 0; v3 = 0;
        for (i = 0; i < 256; i = i + 1) begin
            if (seen0[i]) v0 = v0 + 1;
            if (seen1[i]) v1 = v1 + 1;
            if (seen2[i]) v2 = v2 + 1;
            if (seen3[i]) v3 = v3 + 1;
        end
        check((v0 >= 2) && (v1 >= 2) && (v2 >= 2) && (v3 >= 2),
              "T3 稀疏扫描时 4 个字节各自都取到 >=2 个值");

        // ---- T4 每一位地址都影响图案（mode 0）----
        flips_bad = 0;
        get_pat(21'h0555AA, 3'd0, p_base);
        for (i = 0; i < 21; i = i + 1) begin
            get_pat(21'h0555AA ^ (21'd1 << i), 3'd0, p_flip);
            if (p_flip === p_base) flips_bad = flips_bad + 1;
        end
        check(flips_bad == 0, "T4 21 位地址每一位单独翻转都改变图案（无死位）");

        // ---- T5 mode 0 A full-width signature golden vectors ----
        get_pat(21'h000000, 3'd0, p_base);
        check(p_base === 32'hA5_5A_3C_C3, "T5.1 mode0 addr=0x000000 -> A55A3CC3");
        get_pat(21'h000001, 3'd0, p_base);
        check(p_base === 32'hA4_5B_3D_CB, "T5.2 mode0 addr=0x000001 -> A45B3DCB");
        get_pat(21'h0000FF, 3'd0, p_base);
        check(p_base === 32'h5A_A2_C3_3C, "T5.3 mode0 addr=0x0000FF -> 5AA2C33C");
        get_pat(21'h001800, 3'd0, p_base);
        check(p_base === 32'hA5_9A_3C_C3, "T5.4 mode0 addr=0x001800 -> A59A3CC3");
        get_pat(21'h1FFFFF, 3'd0, p_base);
        check(p_base === 32'hA5_5A_C3_3C, "T5.5 mode0 addr=0x1FFFFF -> A55AC33C");

        // ---- T6 地址 0 的图案非 0（三个模式）----
        get_pat(21'h000000, 3'd0, p_base);
        check(p_base !== 32'h00000000, "T6.1 mode0 addr=0 图案非 0");
        get_pat(21'h000000, 3'd1, p_base);
        check(p_base !== 32'h00000000, "T6.2 mode1 addr=0 图案非 0");
        get_pat(21'h000000, 3'd2, p_base);
        check(p_base !== 32'h00000000, "T6.3 mode2 addr=0 图案非 0（walking-1 第 0 位）");

        // ---- T7 反向对照：旧公式在稀疏扫描下只有 2 种图案 ----
        //   旧公式（2026-10-04 之前写在顶层里的 pat_of）：
        //       { (8'hA5 ^ a[11:4]), (8'h5A ^ a[7:0]), a[11:4], a[3:0] }
        //   在 a = k<<11 时 a[7:0]=0、a[3:0]=0、a[11:4] 只有最低位 a[11]=k[0] 有值
        //   ⇒ **1024 个点只可能得到 2 种图案**。把它算出来当**反向对照**，
        //   证明 T1 的判据确实能抓到那个 bug（即"这个 TB 不是摆设"）。
        //   ★ 注意用**旧参数**（步长 2048，即 a = k<<11），不是现在默认的 2049。
        for (i = 0; i < 1024; i = i + 1) begin
            a_old  = (i << 11) & 21'h1FFFFF;
            old[i] = { (8'hA5 ^ a_old[11:4]), (8'h5A ^ a_old[7:0]),
                       a_old[11:4], a_old[3:0] };
        end
        cnt_old = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            hit = 0;
            for (j = 0; j < i; j = j + 1)
                if (old[i] === old[j]) hit = 1;
            if (!hit) cnt_old = cnt_old + 1;
        end
        check(cnt_old == 2, "T7 反向对照：旧公式在稀疏扫描下只有 2 种图案（证明 T1 抓得到）");

        // ---- T8 mode 1（LFSR）也是单射 ----
        dup_lf = 0;
        for (i = 0; i < 1024; i = i + 1)
            for (j = i + 1; j < 1024; j = j + 1)
                if (lf[i] === lf[j]) dup_lf = dup_lf + 1;
        check(dup_lf == 0, "T8 mode1（LFSR）稀疏扫描 1024 点两两不同（双射）");

        // ---- T9 mode 2/3/4/5 已知值钉死 ----
        get_pat(21'h000000, 3'd2, p_base);          // a[4:0]=0
        check(p_base === 32'h0000_0001, "T9.1 mode2 walking-1 a[4:0]=0 -> 00000001");
        get_pat(21'h00001F, 3'd2, p_base);          // a[4:0]=31
        check(p_base === 32'h8000_0000, "T9.2 mode2 walking-1 a[4:0]=31 -> 80000000");
        get_pat(21'h000000, 3'd3, p_base);
        check(p_base === 32'hFFFF_FFFE, "T9.3 mode3 walking-0 a[4:0]=0 -> FFFFFFFE");
        get_pat(21'h00001F, 3'd3, p_base);
        check(p_base === 32'h7FFF_FFFF, "T9.4 mode3 walking-0 a[4:0]=31 -> 7FFFFFFF");
        get_pat(21'h000000, 3'd4, p_base);          // a[0]=0
        check(p_base === 32'h0000_0000, "T9.5 mode4 全0全1 a[0]=0 -> 00000000");
        get_pat(21'h000001, 3'd4, p_base);          // a[0]=1
        check(p_base === 32'hFFFF_FFFF, "T9.6 mode4 全0全1 a[0]=1 -> FFFFFFFF");
        get_pat(21'h000000, 3'd5, p_base);          // a[0]=0
        check(p_base === 32'h5555_5555, "T9.7 mode5 相邻位交替 a[0]=0 -> 55555555");
        get_pat(21'h000001, 3'd5, p_base);          // a[0]=1
        check(p_base === 32'hAAAA_AAAA, "T9.8 mode5 相邻位交替 a[0]=1 -> AAAAAAAA");

        $display("[TB] tb_sdr_pat_gen done, errors=%0d (sparse_distinct=%0d consecutive=%0d lfsr=%0d bytes=%0d/%0d/%0d/%0d old_formula=%0d)",
                 errors, 1024 - dup_sp, 1024 - dup_cn, 1024 - dup_lf, v0, v1, v2, v3, cnt_old);
        $finish;
    end

    // 看门狗
    initial begin
        #2_000_000;
        $display("[FAIL] tb_sdr_pat_gen 看门狗超时");
        $finish;
    end

endmodule
