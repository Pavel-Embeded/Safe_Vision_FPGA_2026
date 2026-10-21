// ============================================================================
// sd_initializer.v — SD 卡初始化（SafeVision B 链 · 学习阶段 3 + 4）
// ----------------------------------------------------------------------------
// 依据：手册 7.3「上电 → CMD0 → CMD8 → ACMD41 → CMD58 → Ready」
//       7.4「每一个等待外部响应的状态都有独立超时出口」
//
// 命令序列：
//   seq0 CMD0           复位进 idle，期望 R1 = 0x01
//   seq1 CMD8 (arg 1AA) 查询电压与版本，期望 R7；若回 illegal cmd 则判为 v1 卡
//   seq2 CMD55          APP_CMD 前缀（ACMD 必须先发它）
//   seq3 ACMD41         轮询直到 R1 bit0=0（初始化完成）
//   seq4 CMD58 (READ_OCR) 读 OCR，bit30 = CCS 决定是否 SDHC
//
// ★ 易错点（手册 7.3 明列）：
//   - ACMD 忘发 CMD55 前缀
//   - CMD8 的 CRC 字段写错（SPI 模式下 CMD0/CMD8 是会被卡校验 CRC 的）
//   - CMD0 只发一次（本模块只发一次，但失败后允许 start 重试）
//
// ★ 超时（手册 7.4）：本模块有【两个独立的】等待计数器，不共用：
//   to_resp   命令响应等待（每条命令独立清零）
//   to_acmd41 ACMD41 轮询总上限（跨多次重试累积）
// ============================================================================
`include "safevision_defs.vh"

module sd_initializer #(
    // Default remains the existing 100MHz contract. Override when integrating
    // the storage chain in mem_clk (e.g.125MHz -> div156, SCLK<=400kHz).
    parameter [15:0] CLK_DIV_INIT = `SD_DIV_INIT,
    // ★ 2026-10-06 新增（缺陷 28）：CMD0 的 R1 不是 idle 时，最多再重走几次
    //   "CS 高前导 → CS 低 → CMD0"（用于重新同步被上次复位打断的卡）。
    parameter [2:0]  CMD0_RETRY_MAX = 3'd3
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        start,           // 单拍脉冲，触发一次初始化
    output reg         sdhc,            // 1 = SDHC/SDXC（块寻址）
    output reg         init_done,       // 初始化成功（保持到下次 start）
    output reg         init_error,      // 初始化失败（保持到下次 start）
    output reg  [7:0]  err_code,        // 对外主码，见 safevision_defs.vh
    output reg  [7:0]  err_detail,      // B 链内部细分码
    output reg  [7:0]  retry_cnt,       // ACMD41 轮询次数，供观测
    output reg  [3:0]  dbg_state,       // 供 ChipWatcher / 数码管
    // ★ 2026-10-06 新增（板上 SD 初始化不稳定时的诊断）：
    //   dbg_r1  = 最近一次收到的 R1 原始字节（失败时即"挂掉那条命令"的响应）
    //             `FF` = 卡根本没应答（接触/供电）；`05` = 非法命令（卡没听懂 ⇒ 时钟/位序）；
    //             `00` = 卡应答但状态不对；`01` = idle（正常）
    //   dbg_seq = 失败时正处在第几条命令：0=CMD0, 1=CMD8, 2=CMD55, 3=ACMD41
    //             （只报 R1 会被 CMD8 的"回显错但 R1=01"误导，所以要带 seq）
    output wire [7:0]  dbg_r1,
    output wire [2:0]  dbg_seq,

    // ---- 到 spi_master 的字节总线 ----
    // 注：tx_valid / tx_data 由字节引擎组合驱动（output wire），
    //     必须与 spi_master 的 tx_ready 在同一拍完成握手，不能打拍。
    output reg         spi_cs_n,
    output reg  [15:0] spi_clk_div,
    output wire        spi_tx_valid,
    output wire [7:0]  spi_tx_data,
    input  wire        spi_tx_ready,
    input  wire [7:0]  spi_rx_data,
    input  wire        spi_rx_valid
);

    // ------------------------------------------------------------------------
    // 主状态
    // ------------------------------------------------------------------------
    localparam [3:0] M_IDLE  = 4'd0,
                     M_POWER = 4'd1,   // CS 高，发 >=74 个 SCLK
                     M_CSON  = 4'd2,   // CS 拉低 + 1 个哑字节
                     M_CMD   = 4'd3,   // 发 6 字节命令帧
                     M_R1    = 4'd4,   // 轮询 R1（bit7 恒为 0）
                     M_EXTRA = 4'd5,   // 读 R7/R3 的 4 个附加字节
                     M_NEXT  = 4'd6,   // 评估结果，决定下一个命令
                     M_DONE  = 4'd7,
                     M_ERR   = 4'd8;

    // ------------------------------------------------------------------------
    // 字节收发引擎：bstart -> B_SEND -> B_WAIT -> B_IDLE(bdone 一拍)
    // ------------------------------------------------------------------------
    localparam [1:0] B_IDLE = 2'd0, B_SEND = 2'd1, B_WAIT = 2'd2;

    reg  [1:0]  bstate;
    reg         bstart;
    reg  [7:0]  bdata;
    reg  [7:0]  brdata;
    reg         bdone;

    assign spi_tx_valid = (bstate == B_SEND);
    assign spi_tx_data  = bdata;

    // ------------------------------------------------------------------------
    // 寄存器
    // ------------------------------------------------------------------------
    reg  [3:0]  mstate;
    reg  [2:0]  seq;            // 命令序号
    reg  [7:0]  bcnt;           // 8 位：要能比较到 SD_RESP_MAX_BYTES(64)
    reg  [47:0] cmd_sr;         // 命令移位寄存器（MSB 先发）
    reg  [31:0] extra_sr;       // R7 / R3 附加 4 字节
    reg  [7:0]  extra_len;      // 本命令附加字节数
    reg  [7:0]  r1;             // 最近一次 R1
    reg         ver2;           // 1 = 卡支持 CMD8（v2.0+）
    reg  [31:0] acmd41_arg;
    reg  [31:0] to_resp;        // 【独立超时 1】命令响应等待
    reg  [31:0] to_acmd41;      // 【独立超时 2】ACMD41 轮询总上限
    reg  [2:0]  cmd0_try;       // ★ CMD0 已重同步次数（缺陷 28；do_soft_reset 清零）

    // ★ 诊断输出（见端口注释）：必须放在 r1/seq 的**声明之后**（本项目铁律：
    //   先用后声明在 ModelSim 会直接编译不过，且隐式网会另建一根未驱动的网）
    assign dbg_r1  = r1;
    assign dbg_seq = seq;

    // ------------------------------------------------------------------------
    // 命令帧构造：0x40|cmd + arg(MSB 先发) + CRC7
    // ------------------------------------------------------------------------
    function [47:0] make_cmd;
        input [5:0]  idx;
        input [31:0] arg;
        input [7:0]  crc;
        begin
            make_cmd = {(`SD_CMD_PREFIX | {2'b00, idx}),
                        arg[31:24], arg[23:16], arg[15:8], arg[7:0],
                        crc};
        end
    endfunction

    wire [47:0] cmd_frame = (seq == 3'd0) ? make_cmd(`SD_CMD0,  32'h0000_0000,   `SD_CRC_CMD0) :
                            (seq == 3'd1) ? make_cmd(`SD_CMD8,  `SD_CMD8_ARG,     `SD_CRC_CMD8) :
                            (seq == 3'd2) ? make_cmd(`SD_CMD55, 32'h0000_0000,   `SD_CRC_DONT_CARE) :
                            (seq == 3'd3) ? make_cmd(`SD_ACMD41, acmd41_arg,     `SD_CRC_DONT_CARE) :
                                            make_cmd(`SD_CMD58, 32'h0000_0000,   `SD_CRC_DONT_CARE);

    // 本命令是否为 R7/R3（需额外读 4 字节）
    wire [7:0] cmd_extra_len = (seq == 3'd1 || seq == 3'd4) ? 8'd4 : 8'd0;

    // ------------------------------------------------------------------------
    // 字节引擎
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bstate <= B_IDLE;
            brdata <= 8'h00;
            bdone  <= 1'b0;
        end else begin
            // 注：bstart 与 bdata 都由主状态机单独驱动（单驱动源），本块只读，
            //     避免多驱动竞争。
            // ★ 这两个信号的【复位赋值】也必须只留在主状态机里：早期版本在本块
            //   复位分支多写了一次 bdata <= 8'hFF，ModelSim 编译/仿真都不报错
            //   （两个 always 块写同一个 reg 在仿真里只是竞争），但 TD 综合直接
            //   报 HDL-9007 "net 'bdata[7]' is constantly driven from multiple
            //   places" 并中止综合。新增驱动源前先想清楚归谁。
            bdone  <= 1'b0;
            case (bstate)
                B_IDLE : if (bstart) bstate <= B_SEND;
                B_SEND : if (spi_tx_ready) bstate <= B_WAIT;   // 已被 spi_master 接受
                B_WAIT : if (spi_rx_valid) begin
                             brdata <= spi_rx_data;
                             bdone  <= 1'b1;
                             bstate <= B_IDLE;
                         end
                default: bstate <= B_IDLE;
            endcase
        end
    end

    // 软复位：每次 start 都从干净状态开始。
    // ★ 从 M_ERR / M_DONE 重试时必须走这里，否则 bcnt、seq 等残留
    //   会导致上电字节数、命令序号全部错位。
    task do_soft_reset;
        begin
            seq        <= 3'd0;
            bcnt       <= 8'd0;
            cmd_sr     <= 48'h0;
            extra_sr   <= 32'h0;
            extra_len  <= 8'd0;
            r1         <= 8'hFF;
            ver2       <= 1'b0;
            acmd41_arg <= `SD_ACMD41_HCS;
            sdhc       <= 1'b0;
            init_done  <= 1'b0;
            init_error <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
            retry_cnt  <= 8'd0;
            to_resp    <= 32'd0;
            to_acmd41  <= 32'd0;
            cmd0_try   <= 3'd0;      // ★ 每次 start 都从"第 0 次重同步"起算
        end
    endtask

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate      <= M_IDLE;
            seq         <= 3'd0;
            bcnt        <= 6'd0;
            cmd_sr      <= 48'h0;
            extra_sr    <= 32'h0;
            extra_len   <= 8'd0;
            r1          <= 8'hFF;
            ver2        <= 1'b0;
            acmd41_arg  <= `SD_ACMD41_HCS;
            sdhc        <= 1'b0;
            init_done   <= 1'b0;
            init_error  <= 1'b0;
            err_code    <= `ERR_NONE;
            err_detail  <= `DET_NONE;
            retry_cnt   <= 8'd0;
            spi_cs_n    <= 1'b1;
            spi_clk_div <= CLK_DIV_INIT;
            to_resp     <= 32'd0;
            to_acmd41   <= 32'd0;
            dbg_state   <= M_IDLE;
            bstart      <= 1'b0;
            bdata       <= 8'hFF;      // bdata 的唯一驱动源就是本块（见字节引擎注释）
        end else begin
            dbg_state <= mstate;
            bstart    <= 1'b0;      // bstart 只有本块驱动；请求只持续 1 拍

            // 进入错误态即置错误标志；M_ERR 里收到 start 会把它清掉（同一 always 块，后面赋值优先）
            if (mstate == M_ERR) init_error <= 1'b1;

            // 【独立超时 2】ACMD41 轮询总计时：跨多次 CMD55+ACMD41 重试累积，
            // 与 to_resp 完全独立（手册 7.4 要求各等待态不共用计数器）
            if (seq >= 3'd2 && mstate != M_IDLE && mstate != M_DONE && mstate != M_ERR)
                to_acmd41 <= to_acmd41 + 32'd1;

            case (mstate)
            // ------------------------------------------------------------------
            M_IDLE: begin
                spi_cs_n   <= 1'b1;
                spi_clk_div<= CLK_DIV_INIT;      // initialization SCLK <=400kHz
                if (start) begin
                    do_soft_reset;
                    mstate <= M_POWER;
                end
            end
            // ---- 上电：CS 保持高，发 >=74 个 SCLK -----------------------------
            M_POWER: begin
                spi_cs_n <= 1'b1;
                if (bdone) begin
                    if (bcnt == (`SD_POWERUP_BYTES - 1)) begin
                        bcnt   <= 6'd0;
                        seq    <= 3'd0;
                        mstate <= M_CSON;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end else if (bstate == B_IDLE && !bstart) begin
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end
            // ---- 拉低 CS + 1 个哑字节 ----------------------------------------
            M_CSON: begin
                spi_cs_n <= 1'b0;
                if (bdone) begin
                    cmd_sr  <= cmd_frame;
                    bdata   <= cmd_frame[47:40];
                    bstart  <= 1'b1;
                    bcnt    <= 8'd0;
                    to_resp <= 32'd0;
                    mstate  <= M_CMD;
                end else if (bstate == B_IDLE && !bstart) begin
                    bdata  <= 8'hFF;          // 哑字节：CS 拉低后给卡一整字节准备时间
                    bstart <= 1'b1;
                end
            end
            // ---- 发 6 字节命令帧 ---------------------------------------------
            M_CMD: begin
                if (bdone) begin
                    if (bcnt == 6'd5) begin
                        bcnt    <= 6'd0;
                        to_resp <= 32'd0;
                        mstate  <= M_R1;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        cmd_sr <= {cmd_sr[39:0], 8'hFF};
                        bdata  <= cmd_sr[39:32];   // 移位后的新最高字节
                        bstart <= 1'b1;
                    end
                end
            end
            // ---- 轮询 R1：反复发 0xFF 直到 bit7 == 0 ---------------------------
            M_R1: begin
                to_resp <= to_resp + 32'd1;
                if (to_resp == `SD_TO_RESP) begin
                    // 【独立超时出口 1】命令响应等待超时
                    err_code   <= `ERR_SD_INIT;
                    err_detail <= `DET_SD_RESP_TO;
                    mstate     <= M_ERR;
                end else if (bdone) begin
                    if (brdata[7] == 1'b0) begin
                        r1          <= brdata;
                        bcnt        <= 8'd0;
                        extra_sr    <= 32'h0;
                        extra_len   <= cmd_extra_len;
                        if (cmd_extra_len == 8'd0) begin
                            mstate <= M_NEXT;
                        end else begin
                            bdata  <= 8'hFF;
                            bstart <= 1'b1;
                            mstate <= M_EXTRA;
                        end
                    end else if (bcnt >= `SD_RESP_MAX_BYTES) begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_RESP_TO;
                        mstate     <= M_ERR;
                    end else begin
                        bcnt   <= bcnt + 8'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end else if (bstate == B_IDLE && !bstart) begin
                    // 首次进入本状态：必须先发出第一个轮询字节，否则永远等不到响应
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end
            // ---- 读 R7 / R3 的 4 个附加字节 ----------------------------------
            M_EXTRA: begin
                if (bdone) begin
                    extra_sr <= {extra_sr[23:0], brdata};
                    if (bcnt == extra_len - 8'd1) begin
                        bcnt   <= 6'd0;
                        mstate <= M_NEXT;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end
            end
            // ---- 评估，决定下一个命令 ----------------------------------------
            M_NEXT: begin
                case (seq)
                // -------- CMD0：期望已进 idle（★ 不能只认 0x01，见下）--------
                3'd0: begin
                    // ★★ 2026-10-06 板级实测修（缺陷 27）：**原写法 `r1 == 8'h01` 过严**。
                    //   板上用新增的 `R1=`/`SQ=` 诊断抓到真值：`ED=11 R1=03 SQ=0`
                    //   ⇒ CMD0 的 R1 = `0x03` = **bit0(idle) + bit1(erase reset)**
                    //   —— 卡**确实进了 idle**、复位是成功的，但严格等值判断把它判成失败。
                    //   这就是"SD 初始化约 1/10 才成功"的来源之一：卡干净时返 `0x01` 就过，
                    //   带 erase-reset 状态位时返 `0x03` 就被拒（连续按复位时后者居多）。
                    //   正确判据：**bit0(idle) 必须为 1**，且 bit6..bit2
                    //   （非法命令/CRC/擦除序/地址/参数）**全 0**；bit1 是状态位，**容忍**。
                    //
                    // ★★ 2026-10-06 再修（缺陷 28）：**判失败前先"重新同步"**。
                    //   后续又抓到 `R1=02 SQ=0`（bit0=0，**非 idle**）——这种"非 idle 的怪值"
                    //   很像**卡在上一次事务被 FPGA 复位打断后残留的一个数据字节**被 M_R1
                    //   当成了 R1（轮询只要求 bit7=0，残留字节的 bit7 也可能是 0）。
                    //   处置：不是 idle 就**重走一遍 `M_POWER`（CS 高 + 80 拍前导）→
                    //   `M_CSON`（CS 拉低）→ `M_CMD`（CMD0）** —— CS 翻转 + 前导会中止并
                    //   重新同步卡；最多再试 `CMD0_RETRY_MAX` 次，仍不行才判错。
                    if (r1[`SD_R1_IDLE_STATE] && (r1[6:2] == 5'd0)) begin
                        seq    <= 3'd1;
                        mstate <= M_CSON;
                    end else if (cmd0_try < CMD0_RETRY_MAX) begin
                        cmd0_try <= cmd0_try + 3'd1;
                        mstate   <= M_POWER;          // 重新同步：整段重来
                    end else begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_INIT_CMD;
                        mstate     <= M_ERR;
                    end
                end
                // -------- CMD8：期望回显 0xAA；illegal cmd 则判 v1 卡 --------
                3'd1: begin
                    if (r1[`SD_R1_ILLEGAL_CMD]) begin
                        // 卡不认 CMD8 -> v1.x 卡，ACMD41 不带 HCS
                        ver2       <= 1'b0;
                        acmd41_arg <= 32'h0000_0000;
                        seq        <= 3'd2;
                        mstate     <= M_CSON;
                    end else if (extra_sr[7:0] == `SD_CMD8_CHECK) begin
                        // 正确回显 0xAA -> v2.0+ 卡
                        ver2       <= 1'b1;
                        acmd41_arg <= `SD_ACMD41_HCS;
                        seq        <= 3'd2;
                        mstate     <= M_CSON;
                    end else begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_INIT_CMD;   // 电压不匹配 / 回显错
                        mstate     <= M_ERR;
                    end
                end
                // -------- CMD55：期望无 illegal cmd 位 --------
                3'd2: begin
                    if (r1[`SD_R1_ILLEGAL_CMD]) begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_INIT_CMD;
                        mstate     <= M_ERR;
                    end else begin
                        seq    <= 3'd3;
                        mstate <= M_CSON;
                    end
                end
                // -------- ACMD41：bit0=0 表示初始化完成 --------
                3'd3: begin
                    if (r1[`SD_R1_IDLE_STATE]) begin
                        // 仍在初始化：重新走 CMD55 + ACMD41
                        if (to_acmd41 >= `SD_TO_ACMD41) begin
                            // 【独立超时出口 2】ACMD41 轮询总超时
                            err_code   <= `ERR_SD_INIT;
                            err_detail <= `DET_SD_INIT_CMD;
                            mstate     <= M_ERR;
                        end else begin
                            retry_cnt <= retry_cnt + 8'd1;
                            seq       <= 3'd2;
                            mstate    <= M_CSON;
                        end
                    end else begin
                        seq    <= 3'd4;
                        mstate <= M_CSON;
                    end
                end
                // -------- CMD58：读 OCR，bit30 = CCS --------
                3'd4: begin
                    if (extra_sr[31] == 1'b0) begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_NO_OCR;
                        mstate     <= M_ERR;
                    end else begin
                        sdhc       <= ver2 ? extra_sr[30] : 1'b0;
                        init_done  <= 1'b1;
                        mstate     <= M_DONE;
                    end
                end
                default: mstate <= M_ERR;
                endcase
            end
            // ------------------------------------------------------------------
            M_DONE: begin
                spi_cs_n <= 1'b1;
                // init_done 保持，等待 start 重新初始化
                if (start) begin
                    do_soft_reset;
                    mstate <= M_POWER;
                end
            end
            M_ERR: begin
                spi_cs_n <= 1'b1;
                // err_code/err_detail 保持，错误标志可由 C 的可靠性链读取；
                // 再次 start 走完整软复位 + 重试（手册 7.4 过关自测：拔卡后可恢复）
                if (start) begin
                    do_soft_reset;
                    mstate <= M_POWER;
                end
            end
            default: mstate <= M_IDLE;
            endcase
        end
    end

    endmodule
