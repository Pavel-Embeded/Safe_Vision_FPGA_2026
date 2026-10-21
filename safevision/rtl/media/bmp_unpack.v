// ============================================================================
// bmp_unpack.v — BGR888 字节流 → RGB565 像素流（SafeVision 阶段 8 · rtl/media）
// ----------------------------------------------------------------------------
// 依据：手册 7.6.1 表 7-1「行填充 / 字节序与方向」与 7.6.2「BGR888 流进入
//       bmp_unpack，转换为 RGB565 后写入帧缓存，舍入还是截断必须全队统一」
//       docs/interface_spec.md §3.3「bmp_unpack」、§八 待确认项 O-1
//
// 上游：bmp_parser 的像素字节透传口（out_data/out_valid/out_ready/out_sof/out_eof）
//       + 图像信息（width / height / top_down / pixel_off）。
//       bmp_parser 已经把 54 Byte 头与其后的调色板/填充滤掉，本模块拿到的是
//       **从像素数据第一个字节开始**的纯 BGR888 流。
// 下游：像素 FIFO → frame_writer；坐标 (x,y) 供 frame_address_gen 按
//       手册 7.6.2 的 slot_base + ((y*640)+x)*2 算地址。
//
// ★ 三个"最经典"的坑，全部集中在这一个模块里，注释逐条点名：
//   1) 【红蓝颠倒】文件里每个像素 3 个字节的顺序是 B、G、R。转 RGB565 必须写成
//      {R[7:3], G[7:2], B[7:3]}。把 B 当 R 用就是最经典的红蓝对调 bug，
//      在纯红/纯绿/纯蓝测试图上立刻现形（见 tb_bmp_unpack 的 T1）。
//   2) 【行填充】每行字节数必须补到 4 的倍数，公式 ((width*3+3)/4)*4。
//      640 宽、24bpp 恰好整除（1920），但实现仍按公式算，**禁止硬编码 1920**
//      （手册原话批评过"写死"）。填充字节必须丢弃，绝不能当像素字节吃掉。
//   3) 【方向】正高度是自底向上存（bottom-up），负高度是自顶向下（top-down）。
//      本模块统一转换成"左上原点"输出：top_down=1 时 y 随行递增，
//      top_down=0 时 y 从 height-1 递减到 0。
//
// ★ O-1（待确认，未定）：降位是【舍入】还是【截断】尚未全队冻结，故做成
//   parameter ROUNDING。默认 0 = 截断（与参考工程口径一致）；置 1 时用
//   "四舍五入 + 饱和"。定稿后只改顶层例化的这一个 parameter，
//   不要再改本模块内部逻辑。ROUNDING=1 的差异在 tb_bmp_unpack T9 里被显式对比。
//
// ★ 计数口径（手册 7.6.2"把半幅图/坏图被显示的可能性在结构上排除"）：
//   输出像素总数必须严格等于 width*height（640x480 = 307200）。
//   - 少一个（上游提前 eof / 断流）-> error + DET_BMP_TRUNC
//   - 多一个（像素数超限）        -> error + DET_BMP_SIZE
//   两种情况都不会把 done 之外的"半幅图"当成一帧放行。
//
// ★ 实测/文档踩过的坑（interface_spec §一，本项目真实踩过）：
//   1) 从上游收字节必须 `din_valid && din_ready` 双判，只判 din_valid 会在
//      反压期间把同一个字节吃掉很多次。
//   2) "下游取走像素"的清零逻辑放在 case/状态机之外、对所有状态生效：
//      最后一个像素被锁存的那一拍正好也是本图结束、状态跳走的那一拍，
//      清零逻辑若只写在接收态里，pixel_valid 就再也没人清，直接死等超时。
// ============================================================================
`include "safevision_defs.vh"

module bmp_unpack #(
    // O-1：0 = 截断（默认），1 = 舍入（四舍五入 + 饱和）
    parameter ROUNDING = 1'b0
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 上游：bmp_parser 的像素字节透传口 ----
    input  wire [7:0]  din,
    input  wire        din_valid,
    output wire        din_ready,
    input  wire        din_sof,       // 像素段有效（bmp_parser 的 out_sof）
    input  wire        din_eof,       // 与最后一个像素字节同拍

    // ---- 上游：bmp_parser 的图像信息 ----
    input  wire [15:0] width,         // 必须 640
    input  wire [15:0] height,        // 480 或 -480（bit15=1 -> top_down）
    input  wire        top_down,      // 1 = 负高度，自顶向下存
    input  wire [31:0] pixel_off,     // bfOffBits：登记用。上游已按它滤掉头部/调色板，
                                      // 本模块不参与运算，保留端口只为与手册 7.6.2
                                      // 的装载日志口径一致（见文件头说明）。

    // ---- 下游：RGB565 像素流 ----
    output reg  [15:0] pixel,
    output reg         pixel_valid,
    input  wire        pixel_ready,
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    output reg         img_sof,       // 与第一个输出像素同拍
    output reg         img_eof,       // 与最后一个输出像素同拍

    // ---- 状态 ----
    output reg         done,          // 单拍：本图处理结束（成功或出错都置 1）
    output reg         error,         // 电平：出错（保持到下一图开始）
    output reg  [7:0]  err_code,      // 对外主码
    output reg  [7:0]  err_detail,    // B 链内部细分码
    output reg  [3:0]  dbg_state
);

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam [1:0] U_IDLE = 2'd0,
                     U_RUN  = 2'd1,
                     U_DONE = 2'd2,
                     U_ERR  = 2'd3;

    reg  [1:0]  state;
    reg  [15:0] col;          // 行内字节偏移 0..stride-1（含填充字节）
    reg  [15:0] row_i;        // 流内行序号 0..height-1
    reg  [9:0]  px_in_row;    // 行内像素序号 0..width-1
    reg  [1:0]  phase;        // 0=收 B, 1=收 G, 2=收 R 并出一个像素
    reg  [7:0]  b_r, g_r;     // 暂存 B / G 字节
    reg  [31:0] px_cnt;       // 已输出像素数
    reg         full;         // 已凑满 width*height 个像素
    reg         first_pix;    // 下一个输出的像素是不是本图第一个

    // ------------------------------------------------------------------------
    // 组合：行步长 / 像素总数 / 目标 y
    // ------------------------------------------------------------------------
    // 行填充：((width*3+3)/4)*4 —— 按公式算，不写死 1920
    wire [31:0] w3     = {16'd0, width} * 32'd3;
    wire [31:0] stride = ((w3 + 32'd3) >> 2) << 2;

    wire [15:0] w3_16     = w3[15:0];
    wire [15:0] stride_m1 = stride[15:0] - 16'd1;

    // 高度取绝对值：top_down 时 height 的高位是符号位（如 -480 = 0xFE20）
    wire [15:0] h_abs    = top_down ? (~height + 16'd1) : height;
    wire [31:0] px_total = {16'd0, width} * {16'd0, h_abs};

    // 统一左上原点：top_down=1 时 y 递增，否则从 height-1 递减
    wire [15:0] y_calc = top_down ? row_i : (height - 16'd1 - row_i);

    wire        is_pix_byte = (col < w3_16);        // 本字节属于像素
    wire        is_row_last = (col == stride_m1);   // 本行最后一个字节

    // ------------------------------------------------------------------------
    // 组合：BGR -> RGB565（ROUNDING=0 截断 / ROUNDING=1 舍入+饱和）
    // ------------------------------------------------------------------------
    wire [7:0] cb = b_r;      // 文件里第 1 个字节是 B
    wire [7:0] cg = g_r;      // 第 2 个字节是 G
    wire [7:0] cr = din;      // 第 3 个字节是 R

    wire [4:0] r_trunc = cr[7:3];
    wire [5:0] g_trunc = cg[7:2];
    wire [4:0] b_trunc = cb[7:3];

    wire [5:0] r_round_sum = {1'b0, cr[7:3]} + {5'd0, cr[2]};       // 加半个 LSB
    wire [6:0] g_round_sum = {2'b00, cg[7:2]} + {6'd0, cg[1]};
    wire [5:0] b_round_sum = {1'b0, cb[7:3]} + {5'd0, cb[2]};

    wire [4:0] r_round = (r_round_sum > 6'd31) ? 5'd31 : r_round_sum[4:0];  // 饱和
    wire [5:0] g_round = (g_round_sum > 7'd63) ? 6'd63 : g_round_sum[5:0];
    wire [4:0] b_round = (b_round_sum > 6'd31) ? 5'd31 : b_round_sum[4:0];

    wire [4:0] r5 = ROUNDING ? r_round : r_trunc;
    wire [5:0] g6 = ROUNDING ? g_round : g_trunc;
    wire [4:0] b5 = ROUNDING ? b_round : b_trunc;

    // ★ {R[7:3], G[7:2], B[7:3]} —— 顺序写反就是红蓝颠倒
    wire [15:0] pix_calc = {r5, g6, b5};

    wire        byte_taken  = din_valid && din_ready;
    wire        pix_complete = is_pix_byte && (phase == 2'd2);
    wire        last_expected = (px_cnt + 32'd1 == px_total);
    wire        emit_now     = byte_taken && pix_complete && !full;
    wire        overflow_now = byte_taken && pix_complete && full;

    // eof 收尾判定用【本拍之后的像素总数】，而不是"本拍正好出了最后一个像素"。
    // 原因：宽度不是 4 的倍数时（如宽 3 -> 行步长 12，尾随 3 个填充字节），
    // 流的最后几个字节是填充字节，最后一个【像素】字节并不落在 eof 上。
    // 用 "本拍出了最后一个像素" 判收尾会把这种图误报成"像素不足"。
    wire [31:0] px_next = px_cnt + (emit_now ? 32'd1 : 32'd0);

    // 手里端着像素就不再向上游要字节（下游慢不会让上游超时/错位）
    assign din_ready = (state == U_RUN) && !pixel_valid;

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= U_IDLE;
            col        <= 16'd0;
            row_i      <= 16'd0;
            px_in_row  <= 10'd0;
            phase      <= 2'd0;
            b_r        <= 8'h00;
            g_r        <= 8'h00;
            pixel      <= 16'h0000;
            pixel_valid<= 1'b0;
            x          <= 10'd0;
            y          <= 10'd0;
            img_sof    <= 1'b0;
            img_eof    <= 1'b0;
            px_cnt     <= 32'd0;
            full       <= 1'b0;
            first_pix  <= 1'b1;
            done       <= 1'b0;
            error      <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
            dbg_state  <= U_IDLE;
        end else begin
            dbg_state <= state;
            done      <= 1'b0;          // 单拍脉冲

            // ---- 下游把手里这个像素取走了 ----------------------------------
            // ★ 放在 case 之外、对所有状态生效。最后一个像素被锁存的那一拍
            //   正好也是本图结束、state 跳走（U_DONE）的那一拍；清零逻辑若只写在
            //   U_RUN 里，pixel_valid 就再也没人清，直接死等到兜底超时。
            if (pixel_valid && pixel_ready) begin
                pixel_valid <= 1'b0;
                img_sof     <= 1'b0;
                img_eof     <= 1'b0;
            end

            case (state)
            // ------------------------------------------------------------------
            // 等第一个像素字节。★ 收到 din_sof（上游声明"像素段开始"）才进入 RUN：
            //   bmp_parser 的 out_sof 在整个像素段保持为高，所以这里等价于
            //   "第一个字节"，同时又不会把头部/调色板字节误当像素。
            //   本拍不消费字节（din_ready 在 IDLE 为 0），字节会在 U_RUN 里
            //   按 valid && ready 双判消费，不会丢。
            U_IDLE: begin
                if (din_valid && din_sof) begin
                    state      <= U_RUN;
                    error      <= 1'b0;
                    err_code   <= `ERR_NONE;
                    err_detail <= `DET_NONE;
                    col        <= 16'd0;
                    row_i      <= 16'd0;
                    px_in_row  <= 10'd0;
                    phase      <= 2'd0;
                    b_r        <= 8'h00;
                    g_r        <= 8'h00;
                    px_cnt     <= 32'd0;
                    full       <= 1'b0;
                    first_pix  <= 1'b1;
                end
            end
            // ---- 逐字节解析 BGR + 按行步长跳填充 -------------------------------
            U_RUN: begin
                if (byte_taken) begin
                    // (1) 列/行推进（填充字节也走这里）
                    if (is_row_last) begin
                        col       <= 16'd0;
                        row_i     <= row_i + 16'd1;
                        px_in_row <= 10'd0;      // 行末归零，下一行 x 从 0 起
                    end else begin
                        col <= col + 16'd1;
                    end

                    // (2) 像素字节装配；填充字节只推进 col，不参与装配
                    if (is_pix_byte) begin
                        case (phase)
                        2'd0: begin b_r <= din; phase <= 2'd1; end
                        2'd1: begin g_r <= din; phase <= 2'd2; end
                        2'd2: begin
                            if (!full) begin
                                pixel       <= pix_calc;
                                pixel_valid <= 1'b1;
                                x           <= px_in_row;
                                y           <= y_calc[9:0];
                                img_sof     <= first_pix;
                                img_eof     <= last_expected;
                                px_cnt      <= px_cnt + 32'd1;
                                phase       <= 2'd0;
                                first_pix   <= 1'b0;
                                if (last_expected) full <= 1'b1;
                                // 行末那一个像素不在这里 +1（已在 (1) 清 0）
                                if (!is_row_last) px_in_row <= px_in_row + 10'd1;
                            end
                        end
                        default: phase <= 2'd0;
                        endcase
                    end

                    // (3) 结束 / 越界判定（优先级：像素超限 > eof 收尾）
                    if (overflow_now) begin
                        error      <= 1'b1;
                        err_code   <= `ERR_MEDIA_INVALID;
                        err_detail <= `DET_BMP_SIZE;     // 像素数超限
                        state      <= U_ERR;
                        done       <= 1'b1;
                    end else if (din_eof) begin
                        if (px_next == px_total) begin
                            state <= U_DONE;
                            done  <= 1'b1;
                        end else begin
                            error      <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_BMP_TRUNC;  // 像素数不足
                            state      <= U_ERR;
                            done       <= 1'b1;
                        end
                    end
                end
            end
            // ---- 收尾：等最后一个像素被下游取走 --------------------------------
            U_DONE: begin
                if (!pixel_valid) state <= U_IDLE;
            end
            // ---- 出错：保持 error 到下一图开始 ---------------------------------
            U_ERR: begin
                error <= 1'b1;
                if (!pixel_valid) state <= U_IDLE;
            end
            default: state <= U_IDLE;
            endcase
        end
    end

endmodule