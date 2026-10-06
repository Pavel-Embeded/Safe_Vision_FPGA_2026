// ============================================================================
// top_ip_stub.sv — 把**板级顶层** `safevision_top` 拉进仿真的厂商 IP 桩
// ----------------------------------------------------------------------------
// `vendor_ip_stub.sv` 里已有 `sv_system_pll` 与 `sdram` 两个桩（供 top_sdram_loopback 用）。
// 板级顶层还多例化三个 ModelSim **编译不了**的单元，所以补在这里：
//   · `sv_video_vga_pll` / `sv_video_hd_pll` → 内部是 TD 的 `EG_PHY_PLL` 宏
//   · `hdmi_1_4b_transmitter_core_wrapper`   → 安路 RSA 加密（只能 TD 解密）
//   · `hdmi_phy_wrapper`                     → 内部用 `EG_LOGIC_ODDR` 等厂商原语
// 桩的端口/参数名**照抄真件的声明**（`.enc.v` 的模块头是明文，可读），否则绑定不上。
//
// ★★★ 这些桩**不能证明**任何 HDMI 电气/协议层面的东西：
//     · TMDS 串化、DDC/EDID 时序、像素时钟相位关系**全都没有建模**
//     · PLL 只给一个方波，真实频率/抖动/相位差都不建模
//     ⇒ HDMI 合规性仍然只能靠上板实测。
//
// ★ 它能证明什么（`tb_safevision_top.sv` 用到）：
//     · 顶层把 AXI-Stream 真的接上了（`axis_beats` 会涨、`last` 按行出现）
//     · 顶层的复位/锁定/回落/UART/遥测这些**我们自己的逻辑**能跑通
// ============================================================================
`timescale 1ns / 1ps

// ----------------------------------------------------------------------------
// 视频 PLL 桩（VGA 档）：C1 = 像素时钟 25.185 MHz、C2 = 串化时钟 125.93 MHz
//   ★ 真实相位关系不建模；这里只给方波，让像素域逻辑按正确节拍跑。
// ----------------------------------------------------------------------------
module sv_video_vga_pll (
    input  wire refclk,
    input  wire reset,
    output wire extlock,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk2_out
);
    reg pix  = 1'b0;
    reg ser  = 1'b0;
    always #19.853 pix = ~pix;        // 39.706 ns = 25.185 MHz（像素）
    always #3.970  ser = ~ser;        // 7.941 ns  = 125.93 MHz（串化）
    assign extlock  = 1'b1;
    assign clk0_out = ser;            // C0（283 MHz）顶层不用，占位
    assign clk1_out = pix;            // C1 → pixel_clk
    assign clk2_out = ser;            // C2 → serial_clk
endmodule

// ----------------------------------------------------------------------------
// 视频 PLL 桩（HD 档）：C1 = 74.25 MHz、C2 = 371.25 MHz
// ----------------------------------------------------------------------------
module sv_video_hd_pll (
    input  wire refclk,
    input  wire reset,
    output wire extlock,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk2_out
);
    reg pix = 1'b0;
    reg ser = 1'b0;
    always #6.734 pix = ~pix;         // 13.468 ns = 74.25 MHz
    always #1.347 ser = ~ser;         // 2.694 ns  = 371.25 MHz
    assign extlock  = 1'b1;
    assign clk0_out = ser;
    assign clk1_out = pix;
    assign clk2_out = ser;
endmodule

// ----------------------------------------------------------------------------
// HDMI 1.4b 发送核桩
//   · `O_axis_s_ready` 恒 1（顶层会把 `valid && !ready` 锁成 fault，这里永不触发）
//   · 统计被接收的 AXI beat 数 / `last` 数（TB 用层次引用读，验证视频路真的在跑）
//   · `O_video_locked` 上电若干拍后置 1
//   · EDID 触发后给一个固定的 EDID 头（顶层不解析内容）
// ----------------------------------------------------------------------------
module hdmi_1_4b_transmitter_core_wrapper #(
    parameter DEVICE            = "EG",
    parameter HTOTAL            = 2200,
    parameter HSA               = 44,
    parameter HFP               = 88,
    parameter HBP               = 148,
    parameter HACTIVE           = 1920,
    parameter VTOTAL            = 1125,
    parameter VSA               = 5,
    parameter VFP               = 4,
    parameter VBP               = 36,
    parameter VACTIVE           = 1080,
    parameter VIDEO_TPG         = "Enable",
    parameter VIDEO_FORMAT      = "RGB",
    parameter VIDEO_VIC         = 16,
    parameter AUDIO_SAMPLE_RATE = "48K",
    parameter IIC_SCL_DIV       = 125
)(
    input  wire       I_pixel_clk,
    input  wire       I_rst,

    input  wire       I_edid_read_trig,
    output reg        O_edid_read_valid,
    output reg  [7:0] O_edid_read_data,

    input  wire       I_axis_s_user,
    input  wire       I_axis_s_valid,
    input  wire       I_axis_s_last,
    input  wire [23:0] I_axis_s_data,
    output wire       O_axis_s_ready,

    input  wire       I_audio_valid,
    input  wire [23:0] I_audio_left_data,
    input  wire [23:0] I_audio_right_data,

    input  wire       I_acr_valid,
    input  wire [19:0] I_acr_cts,
    input  wire [19:0] I_acr_n,

    output reg        O_video_locked,

    output wire       O_ddc_scl,
    inout  wire       IO_ddc_sda,

    output reg  [9:0] O_ch0_tmds_data,
    output reg  [9:0] O_ch1_tmds_data,
    output reg  [9:0] O_ch2_tmds_data,
    output reg  [9:0] O_clk_tmds_data
);
    // TB 可读的统计量（层次引用）
    integer axis_beats = 0;
    integer axis_lasts = 0;
    integer axis_bad   = 0;      // 不该出现的组合：ready=1 时 valid 却为 0 且 last=1 等

    assign O_axis_s_ready = 1'b1;        // 无背压
    assign O_ddc_scl      = 1'b1;        // 空闲高
    assign IO_ddc_sda     = 1'bz;        // 不驱动（顶层/外部上拉）

    reg [9:0] lock_cnt = 10'd0;
    reg [9:0] edid_cnt = 10'd0;

    always @(posedge I_pixel_clk) begin
        if (I_rst) begin
            O_video_locked    <= 1'b0;
            O_edid_read_valid <= 1'b0;
            O_ch0_tmds_data   <= 10'd0;
            O_ch1_tmds_data   <= 10'd0;
            O_ch2_tmds_data   <= 10'd0;
            O_clk_tmds_data   <= 10'd0;
            lock_cnt          <= 10'd0;
            edid_cnt          <= 10'd0;
            axis_beats        <= 0;
            axis_lasts        <= 0;
        end else begin
            // 上电 64 拍后“锁定”
            if (lock_cnt != 10'h3FF) begin
                lock_cnt <= lock_cnt + 10'd1;
                if (lock_cnt == 10'd63) O_video_locked <= 1'b1;
            end
            // EDID：触发后给 4 拍有效数据（内容固定，顶层不解析）
            if (I_edid_read_trig) begin edid_cnt <= 10'd8; O_edid_read_valid <= 1'b1; end
            else if (edid_cnt != 10'd0) begin
                edid_cnt <= edid_cnt - 10'd1;
                if (edid_cnt == 10'd1) O_edid_read_valid <= 1'b0;
            end
            O_edid_read_data <= 8'h00;   // 顶层未使用

            // AXI-Stream 统计 + 把一位 TMDS 数据透出来（让 TB 能看到“在动”）
            if (I_axis_s_valid) begin
                axis_beats <= axis_beats + 1;
                if (I_axis_s_last) axis_lasts <= axis_lasts + 1;
                O_ch0_tmds_data <= {2'b00, I_axis_s_data[23:16]};
                O_ch1_tmds_data <= {2'b00, I_axis_s_data[15:8]};
                O_ch2_tmds_data <= {2'b00, I_axis_s_data[7:0]};
                O_clk_tmds_data <= 10'h155;
            end
        end
    end

    // 未使用的输入（避免 lint 噪声）
    wire unused = |{ I_audio_valid, I_acr_valid, I_acr_cts, I_acr_n,
                     I_axis_s_user, I_audio_left_data, I_audio_right_data,
                     VIDEO_TPG, VIDEO_FORMAT, VIDEO_VIC, AUDIO_SAMPLE_RATE,
                     IIC_SCL_DIV, DEVICE, HTOTAL, HSA, HFP, HBP, HACTIVE,
                     VTOTAL, VSA, VFP, VBP, VACTIVE };
endmodule

// ----------------------------------------------------------------------------
// TMDS 串化器桩：不建模 OSERDES/ODDR，只把输入的一位透出来供 TB 观察活动
// ----------------------------------------------------------------------------
module hdmi_phy_wrapper #(
    parameter DEVICE = "EG"
)(
    input  wire       I_pixel_clk,
    input  wire       I_serial_clk,
    input  wire       I_rst,
    input  wire [9:0] I_tmds_channel_0,
    input  wire [9:0] I_tmds_channel_1,
    input  wire [9:0] I_tmds_channel_2,
    input  wire [9:0] I_tmds_channel_clk,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p
);
    assign O_tmds_ch0_p = I_tmds_channel_0[0];
    assign O_tmds_ch1_p = I_tmds_channel_1[0];
    assign O_tmds_ch2_p = I_tmds_channel_2[0];
    assign O_tmds_clk_p = I_tmds_channel_clk[0];

    wire unused = |{ I_pixel_clk, I_serial_clk, I_rst, DEVICE,
                     I_tmds_channel_0[9:1], I_tmds_channel_1[9:1],
                     I_tmds_channel_2[9:1], I_tmds_channel_clk[9:1] };
endmodule
