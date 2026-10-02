// ============================================================================
// top_stage5_sector_rd.v — 板级最小验证顶层（SafeVision B 链 · 学习阶段 5）
// ----------------------------------------------------------------------------
// 依据：手册 7.5「向指定 LBA 发 CMD17，收 512 Byte 并通过 UART 回传比对」
//       7.3（CMD0/CMD8 的 CRC7）、7.4（各等待态独立超时）——这两条由被例化的
//       sd_initializer / sd_sector_reader 内部承担，本顶层不重复实现。
//       落点依据：docs/PROJECT_STRUCTURE.md（板级相关一切归 platform/…/）。
//
// 定位：这是【接引脚、不属产品链】的 bring-up 顶层，**不是** A 的产品顶层
//       safevision_top.v（那个负责视频/HDMI/SDRAM/音频）。本文件只做一件事：
//
//         上电等待 → SD 初始化(CMD0/CMD8/ACMD41/CMD58) → 读 LBA=1000 单扇区
//         → 512 Byte 按序经 UART 发出（115200 8N1）
//
//       目的是在板子上复现 tb_sd_sector_reader.sv 已经仿真过的路径，并与电脑侧
//       保存的 lba1000_pc.bin 逐字节比对（见待办清单 M-9）。
//
// ★ 时钟取舍（重要，勿当成产品时钟方案）：
//   板载 50 MHz 晶振经 R7 进 FPGA（原理图网络名 FPGA_GCLK）。
//   本顶层【不接安路 PLL】，全部逻辑只跑这一个 50 MHz 时钟域。
//   理由：bring-up 阶段先排除"IP 配置错"这一层变量，越少依赖越好。
//   代价（都已核对，不影响判定）：
//     - uart_tx 的 CLK_FREQ 改 50_000_000 → DIV = 50M/115200 = 434（误差 0.007%）
//     - spi_master 的 SCLK 由 clk_div 决定（spi_master 只按 clk_div 分频）：
//         SD_DIV_INIT = 124 → 50M/(2*125) = 200 kHz（初始化段，规范允许 100~400 kHz）
//         SD_DIV_FAST = 1   → 50M/(2*2)   = 12.5 MHz（数据段，<= 25 MHz）
//     - safevision_defs.vh 的 SD 超时拍数按 100 MHz 推导，50 MHz 下墙上时间翻倍，
//       只会更宽松，不会把正常路径误判成超时。
//   产品链仍按 docs/interface_spec.md §一：sys_clk=100MHz / mem_clk=125MHz /
//   pixel_clk=25.175MHz，PLL 由 TD IP 提供（A 负责）。
//
// ★ 为什么两个 SD 模块共用一条 SPI 总线：
//   sd_initializer 与 sd_sector_reader 各自带一套「请求→发字节→收字节」引擎
//   （bstate: B_IDLE/B_SEND/B_WAIT），它们的设计就是复用同一个 spi_master：
//   任一时刻只有一个在活动。顶层用 init_done 做二选一：
//     init_done = 0 → 把 initializer 的 tx_valid/tx_data 接到 spi_master
//     init_done = 1 → 切到 reader
//   rx_data/rx_valid 广播给两者——不在活动的那一个 bstate 停在 B_IDLE，
//   只在 bstart 时才离开，因此不会误吞对方的接收字节。
//   sd_ncs = 两个 cs（都低有效）相与：谁拉低就低，都回空闲则为高。
//
// ★ 数据反压（UART 比 SD 慢得多，必须靠 ready 顶住）：
//   UART 115200 每字节约 87 us，512 Byte 约 44.6 ms，远慢于 SD 读时序。
//     uart_tx_valid = rd_data_valid & uart_ready
//     rd_data_ready = uart_tx_valid
//   两者同拍握手一拍：uart 锁存后离开 U_IDLE（tx_ready 变低），reader 下一拍
//   清 data_valid，既不重复发送也不丢字节。reader 在 S_DATA 停 SCLK 等下游，
//   而 S_DATA 本身没有超时计数器（超时只挂在 S_R1 / S_TOKEN），所以"慢发"
//   不会被误判成超时。
//
// ★ LED 状态码（led[3:0]，可直接看，不必接串口）：
//     1 = 上电等待   2 = 发初始化请求   3 = 等 init_done
//     4 = 发读请求   5 = 传输中(512 Byte 正在经 UART 发出)
//     8 = 成功       其余值(0x0?) = 失败，显示错误主码低 4 位
// ============================================================================

module top_stage5_sector_rd #(
    parameter integer CLK_FREQ    = 50_000_000,     // 板载晶振频率（R7）
    parameter integer BAUD        = 115200,
    parameter [31:0]  TARGET_LBA  = 32'd1000,       // 与电脑侧 lba1000_pc.bin 对应
    parameter [23:0]  POWERUP_CYC = 24'd2_500_000   // 上电等待 50ms @50MHz
)(
    // ---- 板级引脚（引脚号见同目录 constraints/pin.adc）----
    input  wire        clk,        // R7   FPGA_GCLK  50 MHz
    input  wire        rst_n,      // A2   KEY_1       低有效按键
    output wire        sd_ncs,     // A12  FPGA_SD_D3  SPI 模式下的片选
    output wire        sd_dclk,    // A14  FPGA_SD_CLK
    output wire        sd_mosi,    // A13  FPGA_SD_CMD
    input  wire        sd_miso,    // B14  FPGA_SD_D0
    output wire        uart_txd,   // D12  网络名 TXD（需复核，见 pin.adc 说明）
    output wire [3:0]  led         // A4/A3/C10/B12 = LED0..LED3
);

    // ------------------------------------------------------------------------
    // 复位：按键是异步源且带抖动，先过同步器再当复位用（复用 A 已验证的 reset_sync）
    // ------------------------------------------------------------------------
    wire rst_sync_n;

    reset_sync u_reset_sync (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_sync_n)
    );

    // ------------------------------------------------------------------------
    // 顶层序列状态
    // ------------------------------------------------------------------------
    localparam [2:0] ST_POWER  = 3'd0,   // 上电等待
                     ST_INIT   = 3'd1,   // 发 init_start 一拍
                     ST_WAIT   = 3'd2,   // 等 init_done / init_error
                     ST_RD     = 3'd3,   // 发 rd_en（valid/ready 握手）
                     ST_STREAM = 3'd4,   // 等 rd_done，期间 512 Byte 随 UART 发出
                     ST_OK     = 3'd5,
                     ST_ERR    = 3'd6;

    reg  [2:0]  st;
    reg  [23:0] pwr_cnt;

    // ------------------------------------------------------------------------
    // 与两个 SD 模块 / spi_master / uart 的连线
    // ------------------------------------------------------------------------
    // sd_initializer
    wire        sdhc;            // 1 = SDHC/SDXC（块寻址），读侧要用
    wire        init_done;
    wire        init_error;
    wire [7:0]  init_err_code;
    wire        init_cs_n;
    wire [15:0] init_clk_div;
    wire        init_tx_valid;
    wire [7:0]  init_tx_data;

    // sd_sector_reader
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid;
    wire        rd_data_last;
    wire        rd_done;
    wire        rd_busy;
    wire        rd_timeout;
    wire        rd_crc16_err;
    wire [7:0]  rd_err_code;
    wire        rd_cs_n;
    wire [15:0] rd_clk_div;
    wire        rd_tx_valid;
    wire [7:0]  rd_tx_data;
    wire [15:0] rd_crc_rx;       // 收到的 CRC（仅留作观察量，本顶层不判）
    wire [3:0]  rd_dbg_state;

    // spi_master 侧（被两者共用）
    wire        spi_tx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;

    // uart_tx 侧
    wire        uart_ready;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    // ------------------------------------------------------------------------
    // SPI 归属二选一：初始化没完成时归 initializer，完成后归 reader
    // ------------------------------------------------------------------------
    wire        spi_use_reader = init_done;

    wire        spi_tx_valid = spi_use_reader ? rd_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_use_reader ? rd_tx_data  : init_tx_data;
    wire [15:0] spi_clk_div  = spi_use_reader ? rd_clk_div  : init_clk_div;

    // 两路片选都是低有效，相与 = 任一拉低即拉低
    assign sd_ncs = init_cs_n & rd_cs_n;

    // ------------------------------------------------------------------------
    // UART 反压握手（详见文件头「数据反压」）
    // ------------------------------------------------------------------------
    assign uart_tx_valid = rd_data_valid & uart_ready;
    assign uart_tx_data  = rd_data;
    assign rd_data_ready = uart_tx_valid;

    // ------------------------------------------------------------------------
    // 请求脉冲
    // ------------------------------------------------------------------------
    // init_start：ST_INIT 只停一拍，sd_initializer 在 M_IDLE 里就是单拍触发
    wire init_start = (st == ST_INIT);
    // rd_en：valid/ready——只在 reader 可接收（rd_ready=1）时才拉高，避免单拍踩空
    wire rd_en      = (st == ST_RD) && rd_ready;

    // ------------------------------------------------------------------------
    // 上电等待计数
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n)
            pwr_cnt <= 24'd0;
        else if (st == ST_POWER)
            pwr_cnt <= pwr_cnt + 24'd1;
    end

    // ------------------------------------------------------------------------
    // 顶层序列
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            st <= ST_POWER;
        end else begin
            case (st)
            // ---- 上电等待：让 SD 卡电源稳定后再发 74+ 个 SCLK ----
            ST_POWER: begin
                if (pwr_cnt >= POWERUP_CYC) st <= ST_INIT;
            end
            // ---- 发一次 init_start ----
            ST_INIT: begin
                st <= ST_WAIT;
            end
            // ---- 等初始化结果（initializer 自带各态独立超时，最终必落到 done/err）----
            ST_WAIT: begin
                if (init_done)       st <= ST_RD;
                else if (init_error) st <= ST_ERR;
            end
            // ---- 发起一次单扇区读 ----
            ST_RD: begin
                if (rd_ready) st <= ST_STREAM;
            end
            // ---- 等读完成；这期间 512 Byte 已被 uart_tx 逐字节取走 ----
            ST_STREAM: begin
                if (rd_done) begin
                    if (rd_timeout || rd_crc16_err || (rd_err_code != 8'h00))
                        st <= ST_ERR;
                    else
                        st <= ST_OK;
                end
            end
            ST_OK:  st <= ST_OK;      // 停住，LED 保持 8
            ST_ERR: st <= ST_ERR;     // 停住，LED 显示错误主码低 4 位
            default: st <= ST_POWER;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // LED 状态码（组合，纯观察用）
    // ------------------------------------------------------------------------
    wire [7:0] err_code_sel = (st == ST_WAIT) ? init_err_code : rd_err_code;

    reg [3:0] led_code;
    always @(*) begin
        case (st)
            ST_POWER : led_code = 4'h1;
            ST_INIT  : led_code = 4'h2;
            ST_WAIT  : led_code = 4'h3;
            ST_RD    : led_code = 4'h4;
            ST_STREAM: led_code = 4'h5;
            ST_OK    : led_code = 4'h8;
            default  : led_code = err_code_sel[3:0];   // ST_ERR：错误主码低 4 位
        endcase
    end

    assign led = led_code;

    // ------------------------------------------------------------------------
    // 例化 1：SD 初始化
    // ------------------------------------------------------------------------
    sd_initializer u_sd_initializer (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .start         (init_start),
        .sdhc          (sdhc),
        .init_done     (init_done),
        .init_error    (init_error),
        .err_code      (init_err_code),
        .err_detail    (),                 // 细分码留待 ChipWatcher 观察
        .retry_cnt     (),
        .dbg_state     (),
        .spi_cs_n      (init_cs_n),
        .spi_clk_div   (init_clk_div),
        .spi_tx_valid  (init_tx_valid),
        .spi_tx_data   (init_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );

    // ------------------------------------------------------------------------
    // 例化 2：SD 单扇区读（CMD17）
    // ------------------------------------------------------------------------
    sd_sector_reader u_sd_sector_reader (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .sdhc          (sdhc),
        .rd_en         (rd_en),
        .rd_addr       (TARGET_LBA),
        .rd_len        (16'd1),            // CMD18 未实现，必须为 1
        .rd_ready      (rd_ready),
        .data          (rd_data),
        .data_valid    (rd_data_valid),
        .data_ready    (rd_data_ready),
        .data_last     (rd_data_last),
        .rd_done       (rd_done),
        .busy          (rd_busy),
        .timeout_err   (rd_timeout),
        .crc16_err     (rd_crc16_err),
        .err_code      (rd_err_code),
        .err_detail    (),
        .crc_rx        (rd_crc_rx),
        .dbg_state     (rd_dbg_state),
        .spi_cs_n      (rd_cs_n),
        .spi_clk_div   (rd_clk_div),
        .spi_tx_valid  (rd_tx_valid),
        .spi_tx_data   (rd_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );

    // ------------------------------------------------------------------------
    // 例化 3：SPI 主机（唯一一份，被上面两个模块分时复用）
    // ------------------------------------------------------------------------
    spi_master #(
        .CLK_FREQ (CLK_FREQ)
    ) u_spi_master (
        .clk        (clk),
        .rst_n      (rst_sync_n),
        .clk_div    (spi_clk_div),
        .cs_n       (sd_ncs),
        .tx_valid   (spi_tx_valid),
        .tx_data    (spi_tx_data),
        .tx_ready   (spi_tx_ready),
        .rx_data    (spi_rx_data),
        .rx_valid   (spi_rx_valid),
        .busy       (spi_busy),
        .sclk       (sd_dclk),
        .mosi       (sd_mosi),
        .miso       (sd_miso)
    );

    // ------------------------------------------------------------------------
    // 例化 4：UART 发送（50 MHz 下 115200 8N1）
    // ------------------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_sync_n),
        .tx_valid  (uart_tx_valid),
        .tx_data   (uart_tx_data),
        .tx_ready  (uart_ready),
        .txd       (uart_txd)
    );

endmodule