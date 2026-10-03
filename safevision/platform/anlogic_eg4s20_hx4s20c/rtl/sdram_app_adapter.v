// ============================================================================
// sdram_app_adapter.v — 逐字事务口 <-> 安路厂商 `sdram` 的 App_* 突发口（突发桥）
// ----------------------------------------------------------------------------
// 背景：核心 framebuffer_loopback_core 只认一个逐字事务口
//   req / wr / addr(word) / wdata / wstrb -> rdata / rdata_valid / ready / init_done
// 仿真时直接接 verification/models/frame_memory_model.sv。
// 厂商 `sdram`（ip/sdram/）暴露的是【应用级突发流】口：
//   App_wr_en / App_rd_en 连发时，App_*_addr **每拍自增**；数据逐拍进/出；
//   读侧过固定延迟后 Sdr_rd_en 有效并给出 Sdr_rd_dout。
//
// ★★ 厂商 app 口的正确形态 = 照抄 M-11（`top_sdram_loopback.v`）—— 这是**唯一**
//   被板上验证跑通 4096 个连续 word（`BAD=0000`）的形态。它的三条要点：
//     ① `App_*_en` **连发** N 拍（M-11 用 128；厂商要 ≥2 拍才认）；
//     ② `App_*_addr` 在连发期间**每拍自增**（`addr = base + 第几拍`）；
//     ③ 突发之间 en **静默若干拍**（M-11 用 `BURST_GAP=16`），且**读写不重叠**。
//   读侧另有一条：响应是**延迟应答**，第 k 个 `Sdr_rd_en` 对应第 k 个读命令（1:1）。
//
// ★★ 2026-10-03 板上实测的教训（务必保留，别再走回头路）：
//   ① "写/读各只拉 1 拍使能" ⇒ 读到**全 FF**（厂商要 ≥2 拍）；
//   ② "同址连发" ⇒ 能写进去但**相邻地址互相覆盖**（向 4 个连续 word 写
//      1111/2222/3333/4444，读回全是最后写入值）；
//   ③ 改成大跨步后 4 个值全对 ⇒ 连发时地址必须每拍自增；
//   ④ **本适配器上一版把读侧的地址推进挂在 `Sdr_rd_en` 上**（`rfi` 只在应答
//      到来时才 +1，于是厂商的应答延迟窗内地址被"钉住"不动）—— 板上用
//      "地址斜坡探针"（写进去的值 = 它的字地址）实测：**一次 16 字预取里
//      只有前 4 个读回是对的，第 5 个起又回到起点的值**
//      （`A0..A3=1000 1001 1002 1003`、`A4..AF` 重复这 4 个；帧级正好 1/4 正确）。
//      ⇒ 结论：**读侧也必须"地址每拍自增"**，不能挂在应答上。
//      本版已按 M-11 形态重写读引擎（发命令与收响应两条独立计数、按 1:1 配对、
//      突发之间留 `RB_GAP` 静默）。
//
// ★ 为什么写侧不改：写引擎本来就是 M-11 形态（`App_wr_en` 连发 `wcnt` 拍、
//   `App_wr_addr = wbase + wi` 每拍 +1、攒字期 en 静默 ≥ 16 拍），且板上证据
//   一致（探针 B 的 4 个字与探针 A 的前 4 个字都落对了）。
// ============================================================================

module sdram_app_adapter (
    input  wire        clk,            // mem_clk 125 MHz
    input  wire        rst_n,          // mem 域低有效

    // ---- 逐字事务口（= mem_ctrl.sdram_*）----
    input  wire        req,
    input  wire        wr,
    input  wire [31:0] addr,           // ★ 字地址（mem_ctrl 内已 addr>>2）
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata,
    output reg         rdata_valid,
    output wire        ready,
    output wire        init_done,

    // ---- 厂商 `sdram` 应用口 ----
    input  wire        Sdr_init_done,
    input  wire        Sdr_init_ref_vld,
    input  wire        Sdr_busy,
    output reg         App_wr_en,
    output reg  [20:0] App_wr_addr,
    output reg  [3:0]  App_wr_dm,
    output reg  [31:0] App_wr_din,
    output reg         App_rd_en,
    output reg  [20:0] App_rd_addr,
    input  wire        Sdr_rd_en,
    input  wire [31:0] Sdr_rd_dout
);

    localparam integer WB = 16;                 // 写突发缓冲深度（word）
    localparam integer RB = 16;                 // 读预取深度（word）
    localparam [5:0]   IDLE_FLUSH = 6'd48;      // 攒字停顿多少拍后强制写出
    localparam [4:0]   RB_GAP     = 5'd16;      // 读突发之间的静默拍数（照 M-11 的 BURST_GAP）

    // ------------------------------------------------------------------
    // 写引擎：攒字 -> 突发写出（M-11 形态：en 连发 + 地址每拍 +1）
    // ------------------------------------------------------------------
    reg [31:0] wbuf [0:WB-1];
    reg [3:0]  wdm  [0:WB-1];
    reg [31:0] wbase;          // 首字字地址
    reg [4:0]  wcnt;           // 已攒字数
    reg [5:0]  widle;          // 攒字停顿计时
    reg        wflush;         // 突发写出中
    reg [4:0]  wi;             // 写出索引

    wire w_accept = req && wr && (wcnt < WB) && !wflush;

    // ------------------------------------------------------------------
    // 读引擎（2026-10-03 重写为 M-11 形态）
    //   发命令：rcmd 期间 en 连发 RB 拍、App_rd_addr 每拍 +1（与响应无关）
    //   收响应：rcv_on 期间每拍 Sdr_rd_en 收一个，按 1:1 顺序进 rbuf
    //   供给  ：收齐 RB 个字后，命中地址就逐字供给上游
    //   ★ 两处 2026-10-03 晚的修正（都被板上/TD 实测揪出来）：
    //     ① 命中判据用**寄存器 `rexp`**（缓冲里下一个待供给字的地址）代替
    //        `rbase + rhead` —— 后者是一个 32 位加法器，实测它经 `ready` 一路进核内
    //        状态机成了**最差路径（−1.562 ns / Logic Level 7 含 ADDER=2）**。
    //     ② 读侧 `ready` 改成**寄存器输出 `r_go`**：把"适配器内部 → 核内状态机"这条
    //        长组合路径切成两段（写侧 ready 不经过它，写握手时序不变）。
    //     ③ **未命中就要起预取，不能要求缓冲已排空**：上一版触发条件含 `rcnt==0`，
    //        于是"跳到缓冲外的地址、但缓冲还有剩"会**永久死等**（板上实测：探针 B
    //        读 0x1035 时缓冲里还有 0x1004.. 的 12 个字 ⇒ 死等 ⇒ 看门狗 ERR=06 ⇒
    //        之后整帧写入全被跳过，报文 `B0..B3=0000` 且 `WR=000000`）。
    // ------------------------------------------------------------------
    reg [31:0] rbuf [0:RB-1];
    reg [31:0] rfbase;         // 本次预取的首字字地址
    reg [31:0] rexp;           // ★ 缓冲中下一个待供给字的地址（替代 rbase+rhead 的加法器）
    reg [4:0]  rcnt;           // 缓冲可用字数
    reg [4:0]  rhead;          // 供给索引（只用于 rbuf 取数；地址比较走 rexp）
    reg        rcmd;           // 正在连发读命令
    reg [4:0]  rcmd_i;         // 已发命令数
    reg        rcv_on;         // 正在收响应
    reg [4:0]  rcv_i;          // 已收响应数
    reg [4:0]  rgap;           // 突发之间的静默计数
    reg        r_go;           // ★ 读侧 ready 的寄存器输出
    reg        r_sv;           // 供给后：本拍置位，下一拍给 rdata_valid

    wire r_hit   = (rcnt != 5'd0) && (addr == rexp);          // 命中缓冲（无加法器）
    wire r_serve = req && !wr && !r_sv && !rcmd && (rcv_i == 5'd0) && r_hit;
    // 未命中（缓冲空 **或地址跳变**）⇒ 只要不在预取/供给中且过了突发静默就可以起预取
    wire r_trig  = req && !wr && !r_sv && !rcmd && !rcv_on && !r_hit && (rgap == 5'd0);

    assign init_done = Sdr_init_done;
    // 读侧 ready 走寄存器 r_go（核心 mem_read_burst 用 ready 计 sent）；
    // 未命中时保持 req、不发 ready（核心会等），由本模块起一次预取。
    assign ready = wr ? ((wcnt < WB) && !wflush) : r_go;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wbase <= 32'd0; wcnt <= 5'd0; widle <= 6'd0; wflush <= 1'b0; wi <= 5'd0;
            rfbase<= 32'd0; rexp <= 32'd0; rcnt <= 5'd0; rhead <= 5'd0;
            rcmd  <= 1'b0;  rcmd_i <= 5'd0; rcv_on <= 1'b0; rcv_i <= 5'd0; rgap <= 5'd0;
            r_go  <= 1'b0;  r_sv <= 1'b0;
            rdata <= 32'd0; rdata_valid <= 1'b0;
            App_wr_en <= 1'b0; App_wr_addr <= 21'd0; App_wr_dm <= 4'h0; App_wr_din <= 32'd0;
            App_rd_en <= 1'b0; App_rd_addr <= 21'd0;
        end else begin
            App_wr_en   <= 1'b0;
            App_rd_en   <= 1'b0;
            rdata_valid <= 1'b0;

            // ---------------- 写引擎（M-11 形态，保持不动）----------------
            if (w_accept) begin
                wbuf[wcnt] <= wdata;
                wdm [wcnt] <= ~wstrb;              // dm=0 写该字节
                if (wcnt == 5'd0) wbase <= addr;
                wcnt  <= wcnt + 5'd1;
                widle <= 6'd0;
            end else if (wcnt != 5'd0 && !wflush) begin
                widle <= widle + 6'd1;
            end

            if (wflush) begin
                // ★ en 连发、地址每拍 +1、数据逐拍送（与 M-11 一致）
                App_wr_en   <= 1'b1;
                App_wr_addr <= wbase[20:0] + wi;
                App_wr_din  <= wbuf[wi];
                App_wr_dm   <= wdm [wi];
                if (wi == wcnt - 5'd1) begin
                    wflush <= 1'b0; wcnt <= 5'd0; widle <= 6'd0; wi <= 5'd0;
                end else begin
                    wi <= wi + 5'd1;
                end
            end else if (wcnt != 5'd0 && ((wcnt == WB) || (widle >= IDLE_FLUSH))) begin
                wflush <= 1'b1; wi <= 5'd0;
            end

            // ---------------- 读引擎（M-11 形态）----------------
            // ① 发读命令：en 连发 RB 拍，App_rd_addr **每拍 +1**（不挂在 Sdr_rd_en 上）
            if (rcmd) begin
                App_rd_en   <= 1'b1;
                App_rd_addr <= rfbase[20:0] + {15'd0, rcmd_i};
                if (rcmd_i == RB - 5'd1) begin
                    rcmd   <= 1'b0;
                    rcmd_i <= 5'd0;
                end else begin
                    rcmd_i <= rcmd_i + 5'd1;
                end
            end

            // ①b 读侧 ready 的寄存器化：只有"命中且上一拍没给过 ready"才抬一拍
            r_go <= r_serve && !r_go;

            if (rcv_on && Sdr_rd_en) begin
                // ② 收响应：第 k 个 Sdr_rd_en = 第 k 个命令的返回（1:1，照 M-11/例程）
                rbuf[rcv_i] <= Sdr_rd_dout;
                if (rcv_i == RB - 5'd1) begin
                    rcv_on <= 1'b0;
                    rcv_i  <= 5'd0;
                    rexp   <= rfbase;              // 缓冲就绪：下一个待供给字 = 本次预取首字
                    rcnt   <= RB;
                    rhead  <= 5'd0;
                    rgap   <= RB_GAP;              // 突发之间静默（M-11 的 BURST_GAP）
                end else begin
                    rcv_i <= rcv_i + 5'd1;
                end
            end else if (r_go) begin
                // ③ 握手成立（ready 已在上一拍给出）：取数、推进期望地址，下一拍给 rdata_valid
                rdata <= rbuf[rhead];
                r_sv  <= 1'b1;
                rhead <= rhead + 5'd1;
                rcnt  <= rcnt  - 5'd1;
                rexp  <= rexp  + 32'd1;
            end else if (r_sv) begin
                rdata_valid <= 1'b1;
                r_sv        <= 1'b0;
            end else if (rgap != 5'd0) begin
                rgap <= rgap - 5'd1;
            end else if (r_trig) begin
                // ④ 未命中（缓冲空 **或地址跳变**）-> 从请求地址起连发 RB 拍读命令
                rcmd   <= 1'b1;
                rcv_on <= 1'b1;
                rfbase <= addr;
                rcmd_i <= 5'd0;
                rcv_i  <= 5'd0;
            end
        end
    end

endmodule
