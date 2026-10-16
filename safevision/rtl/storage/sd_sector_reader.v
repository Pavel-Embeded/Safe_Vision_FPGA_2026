// ============================================================================
// sd_sector_reader.v — SD 单扇区读（SafeVision B 链 · 学习阶段 4 + 5）
// ----------------------------------------------------------------------------
// 依据：手册 7.5「向指定 LBA 发 CMD17，收 512 Byte 并通过 UART 回传比对」
//
// 流程：CMD17(6 字节) -> 等 R1(bit7==0) -> 等数据令牌 0xFE -> 收 512 Byte
//       -> 收 2 Byte CRC16 -> 比对
//
// ★ 手册 7.5 明列的三个易错点，本模块对应处理：
//   1) 把数据令牌当数据字节    -> S_TOKEN 收到 0xFE 才进 S_DATA
//   2) 漏收 2 Byte CRC 错位     -> 专门 S_CRC 状态吃掉 2 字节
//   3) LBA 字节序写反          -> rd_addr 作为 32bit 参数整体 MSB 先发
//
// ★ 地址语义：sdhc=1 时 rd_addr 是【块地址】；sdhc=0 时是【字节地址】，
//   本模块在 SDSC 模式下自动左移 9 位换算。
//
// ★ 超时：to_resp（命令响应）与 to_data（数据令牌）两个独立计数器。
//
// ★ 未实现：CMD18 多扇区读（rd_len 目前必须为 1，否则报错）。
//   CMD18 需要额外的 STOP_TRANSMISSION，留到带宽优化阶段再做。
// ============================================================================
`include "safevision_defs.vh"

module sd_sector_reader #(
    // Default remains div1 at100MHz (25MHz). At125MHz use div2, not div1.
    parameter [15:0] CLK_DIV_FAST = `SD_DIV_FAST
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 配置 ----
    input  wire        sdhc,            // 来自 sd_initializer

    // ---- 读请求 ----
    input  wire        rd_en,           // 单拍脉冲
    input  wire [31:0] rd_addr,         // LBA（见上方地址语义）
    input  wire [15:0] rd_len,          // 扇区数，当前必须为 1
    output wire        rd_ready,        // 可接受请求

    // ---- 数据输出（valid/ready，见 interface_spec §3.1）----
    output wire [7:0]  data,
    output wire        data_valid,
    input  wire        data_ready,
    output wire        data_last,       // 本块最后一个字节

    // ---- 完成与状态 ----
    output reg         rd_done,         // 单拍脉冲
    output reg         busy,
    output reg         timeout_err,
    output reg         crc16_err,
    output reg  [7:0]  err_code,        // 对外主码
    output reg  [7:0]  err_detail,      // 内部细分码
    output reg  [15:0] crc_rx,          // 收到的 CRC（供比对留证）
    output reg  [3:0]  dbg_state,

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
    localparam [3:0] S_IDLE  = 4'd0,
                     S_CSON  = 4'd1,   // CS 拉低 + 1 个哑字节
                     S_CMD   = 4'd2,   // 发 6 字节 CMD17
                     S_R1    = 4'd3,   // 等 R1
                     S_TOKEN = 4'd4,   // 等数据令牌 0xFE
                     S_DATA  = 4'd5,   // 收 512 Byte
                     S_CRC   = 4'd6,   // 收 2 Byte CRC16
                     S_DONE  = 4'd7,
                     S_ERR   = 4'd8;

    // ------------------------------------------------------------------------
    // 字节收发引擎（与 sd_initializer 同一结构）
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
    reg  [7:0]  bcnt;          // 8 位：要能比较到 SD_RESP_MAX_BYTES(64)
    reg  [47:0] cmd_sr;
    reg  [9:0]  byte_cnt;      // 0..512
    reg  [15:0] crc_acc;
    reg  [7:0]  dbyte;
    reg         dvalid;
    reg  [31:0] to_resp;       // 【独立超时 1】命令响应
    reg  [31:0] to_data;       // 【独立超时 2】数据令牌/卡忙

    wire [15:0] crc_rx_next = {crc_rx[7:0], brdata};

    // ------------------------------------------------------------------------
    // CRC16-CCITT (XMODEM)：poly 0x1021，init 0x0000，MSB first
    // ★ 算法实现在 rtl/common/crc16_ccitt.v —— 此前本模块与 frame_writer.v
    //   各写了一份同名函数，两处必须永远一致（CRC 口径不一致是最难查的 bug），
    //   故抽成公共模块，本处只做例化。
    //   纯组合步进器：收到一个字节时把 crc_acc <= crc_next_val 即可。
    //   （例化放在寄存器声明之后，避免 vlog 把前置引用误判为隐式网线。）
    // ------------------------------------------------------------------------
    wire [15:0] crc_next_val;
    crc16_ccitt u_crc16 (
        .crc_in  (crc_acc),
        .data    (brdata),
        .crc_out (crc_next_val)
    );

    assign rd_ready   = (mstate == S_IDLE);
    assign data       = dbyte;
    assign data_valid = dvalid;
    assign data_last  = dvalid && (byte_cnt == `SD_SECTOR_BYTES);

    // CMD17 命令帧：0x40|17 + arg(MSB 先发) + CRC
    wire [31:0] cmd_arg = sdhc ? rd_addr : {rd_addr[22:0], 9'b0};
    wire [47:0] cmd_frame = {(`SD_CMD_PREFIX | {2'b00, `SD_CMD17}),
                             cmd_arg[31:24], cmd_arg[23:16], cmd_arg[15:8], cmd_arg[7:0],
                             `SD_CRC_DONT_CARE};

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
                B_SEND : if (spi_tx_ready) bstate <= B_WAIT;
                B_WAIT : if (spi_rx_valid) begin
                             brdata <= spi_rx_data;
                             bdone  <= 1'b1;
                             bstate <= B_IDLE;
                         end
                default: bstate <= B_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate      <= S_IDLE;
            bcnt        <= 6'd0;
            cmd_sr      <= 48'h0;
            byte_cnt    <= 10'd0;
            crc_acc     <= 16'h0;
            crc_rx      <= 16'h0;
            dbyte       <= 8'h00;
            dvalid      <= 1'b0;
            rd_done     <= 1'b0;
            busy        <= 1'b0;
            timeout_err <= 1'b0;
            crc16_err   <= 1'b0;
            err_code    <= `ERR_NONE;
            err_detail  <= `DET_NONE;
            spi_cs_n    <= 1'b1;
            spi_clk_div <= CLK_DIV_FAST;
            to_resp     <= 32'd0;
            to_data     <= 32'd0;
            dbg_state   <= S_IDLE;
            bstart      <= 1'b0;
            bdata       <= 8'hFF;      // bdata 的唯一驱动源就是本块（见字节引擎注释）
        end else begin
            rd_done   <= 1'b0;
            dbg_state <= mstate;
            bstart    <= 1'b0;      // bstart 只有本块驱动；请求只持续 1 拍
            busy      <= (mstate != S_IDLE);

            case (mstate)
            // ------------------------------------------------------------------
            S_IDLE: begin
                spi_cs_n    <= 1'b1;
                spi_clk_div <= CLK_DIV_FAST;    // default-speed data SCLK <=25MHz
                dvalid      <= 1'b0;
                if (rd_en) begin
                    if (rd_len != 16'd1) begin
                        // CMD18 未实现，明确报错而不是静默错读
                        err_code   <= `ERR_SD_IO;
                        err_detail <= `DET_SD_TOKEN_TO;
                        rd_done    <= 1'b1;
                    end else begin
                        timeout_err <= 1'b0;
                        crc16_err   <= 1'b0;
                        err_code    <= `ERR_NONE;
                        err_detail  <= `DET_NONE;
                        crc_acc     <= 16'h0;
                        crc_rx      <= 16'h0;
                        byte_cnt    <= 10'd0;
                        bcnt        <= 6'd0;
                        to_resp     <= 32'd0;
                        to_data     <= 32'd0;
                        mstate      <= S_CSON;
                    end
                end
            end
            // ---- 拉低 CS + 哑字节 --------------------------------------------
            S_CSON: begin
                spi_cs_n <= 1'b0;
                if (bdone) begin
                    cmd_sr <= cmd_frame;
                    bdata  <= cmd_frame[47:40];
                    bstart <= 1'b1;
                    bcnt   <= 8'd0;
                    mstate <= S_CMD;
                end else if (bstate == B_IDLE && !bstart) begin
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end
            // ---- 发 6 字节命令帧 ---------------------------------------------
            S_CMD: begin
                if (bdone) begin
                    if (bcnt == 6'd5) begin
                        bcnt    <= 6'd0;
                        to_resp <= 32'd0;
                        mstate  <= S_R1;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        cmd_sr <= {cmd_sr[39:0], 8'hFF};
                        bdata  <= cmd_sr[39:32];
                        bstart <= 1'b1;
                    end
                end
            end
            // ---- 等 R1 --------------------------------------------------------
            S_R1: begin
                to_resp <= to_resp + 32'd1;
                if (to_resp == `SD_TO_RESP) begin
                    timeout_err <= 1'b1;
                    err_code    <= `ERR_SD_IO;
                    err_detail  <= `DET_SD_RESP_TO;
                    mstate      <= S_ERR;
                end else if (bdone) begin
                    if (brdata[7] == 1'b0) begin
                        if (brdata != 8'h00) begin
                            // R1 非 0：卡片报错（地址越界 / 参数错 / CRC 错）
                            err_code    <= `ERR_SD_IO;
                            err_detail  <= `DET_SD_RESP_TO;
                            timeout_err <= 1'b1;
                            mstate      <= S_ERR;
                        end else begin
                            to_data <= 32'd0;
                            mstate  <= S_TOKEN;
                        end
                    end else if (bcnt >= `SD_RESP_MAX_BYTES) begin
                        timeout_err <= 1'b1;
                        err_code    <= `ERR_SD_IO;
                        err_detail  <= `DET_SD_RESP_TO;
                        mstate      <= S_ERR;
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
            // ---- 等数据令牌 0xFE ---------------------------------------------
            S_TOKEN: begin
                to_data <= to_data + 32'd1;
                if (to_data == `SD_TO_DATA) begin
                    timeout_err <= 1'b1;
                    err_code    <= `ERR_SD_IO;
                    err_detail  <= `DET_SD_TOKEN_TO;
                    mstate      <= S_ERR;
                end else if (bdone) begin
                    if (brdata == `SD_TOKEN_DATA_START) begin
                        mstate <= S_DATA;
                    end else if (brdata[7:5] == 3'b000) begin
                        // 数据错误令牌（高 3 位为 0）：卡侧上报了错误
                        timeout_err <= 1'b1;
                        err_code    <= `ERR_SD_IO;
                        err_detail  <= `DET_SD_TOKEN_TO;
                        mstate      <= S_ERR;
                    end else begin
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end else if (bstate == B_IDLE && !bstart) begin
                    // 首次进入本状态：必须先发出第一个轮询字节，否则永远等不到令牌
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end
            // ---- 收 512 字节，带 ready 反压 ----------------------------------
            S_DATA: begin
                if (dvalid) begin
                    if (data_ready) begin
                        dvalid <= 1'b0;
                        if (byte_cnt == `SD_SECTOR_BYTES) begin
                            bcnt   <= 6'd0;
                            bdata  <= 8'hFF;
                            bstart <= 1'b1;
                            mstate <= S_CRC;
                        end
                    end
                end else if (bdone) begin
                    dbyte    <= brdata;
                    dvalid   <= 1'b1;
                    crc_acc  <= crc_next_val;
                    byte_cnt <= byte_cnt + 10'd1;
                end else if (bstate == B_IDLE) begin
                    // 下游未 ready 时不发 0xFF，SCLK 停住，卡被自然暂停
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end
            // ---- 收 2 Byte CRC16 ---------------------------------------------
            S_CRC: begin
                if (bdone) begin
                    crc_rx <= crc_rx_next;
                    if (bcnt == 6'd1) begin
                        if (crc_rx_next != crc_acc) begin
                            crc16_err <= 1'b1;
                            err_code <= `ERR_SD_IO;
                            err_detail <= `DET_SD_DATA_CRC;
                        end
                        mstate <= S_DONE;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end
            end
            // ------------------------------------------------------------------
            S_DONE: begin
                spi_cs_n <= 1'b1;
                rd_done  <= 1'b1;
                mstate   <= S_IDLE;
            end
            S_ERR: begin
                spi_cs_n <= 1'b1;
                rd_done  <= 1'b1;
                mstate   <= S_IDLE;
            end
            default: mstate <= S_IDLE;
            endcase
        end
    end

endmodule
