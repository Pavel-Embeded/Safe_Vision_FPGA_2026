// ============================================================================
// wav_reader.v — WAV 容器解析 + 16bit 双声道 PCM 输出（SafeVision B04 · rtl/media）
// ----------------------------------------------------------------------------
// 依据：手册 7.16.3「媒体格式学习顺序」、8.6「从 I²S 音频到 HDMI 音频链（必须改写）」
//       及其后的「技术纠错：音频不走外部 I²S Codec」：
//         B 从 TF 卡读出 WAV，解析 RIFF / fmt / data 得到 48 kHz、16 bit、双声道
//         PCM；"fmt 与 data 之间的未知块按 chunk size 跳过并做边界检查"；
//         "WAV 接受条件由 B 保证"。B 的职责止于"提供正确的 PCM 样本"。
//       docs/interface_spec.md §3.6「wav_reader」、§七 决策 D-7
//
// 上游：file_streamer 的字节流（data/valid/ready/sof/eof），与 bmp_parser 分时复用。
// 下游：pcm_ring（经异步 FIFO 跨域）。B04 不做 48 kHz 节拍 / 仲裁 / 打包。
//
// 接受条件（interface_spec D-7）：PCM format code = 1、双声道、48 kHz、16 bit。
// 其余一律报错并请求回退提示音（fallback_req）。
//
// ★ 三个 WAV 解析的经典坑，逐条点名：
//   1) 【RIFF 全部多字节字段是小端】size / sample_rate / chunk_size 都要按
//      "新字节从高端进"装配（{din, old[31:8]}）。装反了 48000 会变成天文数字。
//   2) 【fmt 与 data 之间可能有别的块】不许假设两者紧挨着。有的编码器会插
//      LIST / fact / cue 等；必须按 8 Byte 块头里的 chunk size 跳过，且
//      RIFF 规定块按偶数对齐，size 为奇数时还要多丢 1 个填充字节。
//      这是 WAV 解析最经典的坑（只找 "data" 字符串的写法在这里必翻车）。
//   3) 【左右声道顺序】data 里每对样本是 L(2 Byte) 再 R(2 Byte)，均为小端。
//      输出 sample[31:0] = {pcm_r[15:0], pcm_l[15:0]}（左声道在低 16 位），
//      与 §3.6 pcm_ring 的 wr_data 口径一致。写反了就是左右声道对调。
//
// ★ 错误码口径：对外主码 `ERR_WAV`(0x07)，细分码 `DET_WAV_*`(0x71–0x74)，
//   两者都已登记在 rtl/include/fault_code_defs.vh；
//   依据 interface_spec §6.1 表 9-3、§6.2 细分码表与决策 D-7。
//
// ★ 实测/文档踩过的坑（interface_spec §一）：
//   1) 收字节必须 `din_valid && din_ready` 双判。
//   2) "下游取走样本"的清零逻辑放在 case/状态机之外，对所有状态生效，
//      否则 data 最后一个样本锁存后 pcm_valid 再也没人清。
// ============================================================================
`include "safevision_defs.vh"

module wav_reader (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        start,          // 单拍：开始解析一个 WAV
    input  wire [31:0] first_clus,     // 来自 file_index 的 WAV 索引口（交 file_streamer 用，
                                       // 本模块不参与解析，保留端口是为控制面完整/日志）
    input  wire [31:0] file_size,      // 文件声明长度，用于容器越界校验
    input  wire [7:0]  track_id,       // 音轨编号，透传

    // ---- 字节流输入（复用 file_streamer 的 data/valid/ready + eof）----
    input  wire [7:0]  din,
    input  wire        din_valid,
    output wire        din_ready,
    input  wire        din_eof,        // 与最后一个字节同拍：用于容器越界/截断判定

    // ---- 解析结果 ----
    output reg  [15:0] fmt_code,       // 必须 = 1（PCM）
    output reg  [15:0] num_channels,   // 必须 = 2
    output reg  [31:0] sample_rate,    // 必须 = 48000
    output reg  [15:0] bits_per_sample,// 必须 = 16
    output reg  [31:0] data_offset,    // PCM 数据在流内的起始字节偏移（data 块头之后）
    output reg  [31:0] data_size,      // PCM 总字节数（data 块 size）
    output reg         header_done,    // 单拍：fmt 块解析完成（成败都置）

    // ---- PCM 输出 ----
    output reg  [15:0] pcm_l,          // 左声道，有符号
    output reg  [15:0] pcm_r,          // 右声道，有符号
    output reg  [31:0] sample,         // {pcm_r, pcm_l}，供 32bit CDC FIFO 直连
    output reg         pcm_valid,
    input  wire        pcm_ready,
    output reg         pcm_end,        // 与最后一个样本同拍

    // ---- 状态 ----
    output reg  [7:0]  track_id_o,     // 透传给 pcm_ring
    output reg         wav_error,      // 电平
    output reg  [7:0]  err_code,       // 对外主码
    output reg  [7:0]  err_detail,     // B 链内部细分码
    output reg         fallback_req,   // 请求回退到提示音
    output reg  [31:0] samples_rd,     // 已输出样本对数
    output reg  [3:0]  dbg_state
);

    // WAV 细分码 DET_WAV_* 已登记在 rtl/include/fault_code_defs.vh（v1.6 补登记）

    // 块标识（小端装配后的 32bit 值）
    localparam [31:0] ID_RIFF = 32'h46464952;   // "RIFF"
    localparam [31:0] ID_WAVE = 32'h45564157;   // "WAVE"
    localparam [31:0] ID_FMT  = 32'h20746D66;   // "fmt "
    localparam [31:0] ID_DATA = 32'h61746164;   // "data"

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam [2:0] W_IDLE  = 3'd0,
                     W_HDR   = 3'd1,   // 12 Byte RIFF 头
                     W_CHUNK = 3'd2,   // 8 Byte 块头
                     W_FMT   = 3'd3,   // fmt 块体
                     W_SKIP  = 3'd4,   // 未知块体（含偶对齐填充）
                     W_DATA  = 3'd5,   // data 块体 -> PCM
                     W_END   = 3'd6,
                     W_ERR   = 3'd7;

    reg  [2:0]  state;
    reg  [31:0] byte_cnt;     // 已消费字节数（流内偏移）
    reg  [3:0]  hdr_idx;      // RIFF 头内字节序号 0..11
    reg  [31:0] riff_r;       // "RIFF"
    reg  [31:0] riff_sz;      // 声明的文件大小
    reg  [31:0] wave_r;       // "WAVE"
    reg  [2:0]  chunk_idx;    // 块头内字节序号 0..7
    reg  [31:0] cid;          // 块标识
    reg  [31:0] csz;          // 块大小
    reg  [4:0]  fmt_idx;      // fmt 块体内字节序号
    reg  [31:0] fmt_size;     // fmt 块大小
    reg  [15:0] f_code;
    reg  [15:0] f_ch;
    reg  [31:0] f_rate;
    reg  [15:0] f_bits;
    reg         fmt_seen;     // 已见到合法 fmt
    reg  [31:0] skip_cnt;     // 待跳过字节数（未知块体）
    reg         pad_pend;     // 未知块 size 为奇数时还要丢 1 Byte
    reg  [31:0] dleft;        // data 块内剩余字节
    reg  [1:0]  phase;        // 0..3 收集一对样本的 4 个字节
    reg  [7:0]  l_lo, l_hi, r_lo;

    // ------------------------------------------------------------------------
    // 组合：小端装配的"本拍新值" / 收字节门控
    // ------------------------------------------------------------------------
    wire [31:0] csz_nxt  = {din, csz[31:8]};
    wire [31:0] wave_nxt = {din, wave_r[31:8]};
    wire [15:0] f_bits_nxt = {din, f_bits[15:8]};
    // fmt 块最后一个字节（idx=15）时 f_bits 尚未落寄存器，用含本字节的装配值
    wire [15:0] bits_v = (fmt_idx == 5'd15) ? f_bits_nxt : f_bits;

    wire        byte_taken = din_valid && din_ready;

    assign din_ready = (state == W_DATA) ? !pcm_valid
                     : ((state == W_HDR) || (state == W_CHUNK) ||
                        (state == W_FMT) || (state == W_SKIP));

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= W_IDLE;
            byte_cnt       <= 32'd0;
            hdr_idx        <= 4'd0;
            riff_r         <= 32'd0;
            riff_sz        <= 32'd0;
            wave_r         <= 32'd0;
            chunk_idx      <= 3'd0;
            cid            <= 32'd0;
            csz            <= 32'd0;
            fmt_idx        <= 5'd0;
            fmt_size       <= 32'd0;
            f_code         <= 16'd0;
            f_ch           <= 16'd0;
            f_rate         <= 32'd0;
            f_bits         <= 16'd0;
            fmt_seen       <= 1'b0;
            skip_cnt       <= 32'd0;
            pad_pend       <= 1'b0;
            dleft          <= 32'd0;
            phase          <= 2'd0;
            l_lo           <= 8'h00;
            l_hi           <= 8'h00;
            r_lo           <= 8'h00;
            fmt_code       <= 16'd0;
            num_channels   <= 16'd0;
            sample_rate    <= 32'd0;
            bits_per_sample<= 16'd0;
            data_offset    <= 32'd0;
            data_size      <= 32'd0;
            header_done    <= 1'b0;
            pcm_l          <= 16'd0;
            pcm_r          <= 16'd0;
            sample         <= 32'd0;
            pcm_valid      <= 1'b0;
            pcm_end        <= 1'b0;
            track_id_o     <= 8'd0;
            wav_error      <= 1'b0;
            err_code       <= `ERR_NONE;
            err_detail     <= `DET_NONE;
            fallback_req   <= 1'b0;
            samples_rd     <= 32'd0;
            dbg_state      <= W_IDLE;
        end else begin
            dbg_state   <= state;
            header_done <= 1'b0;    // 单拍脉冲

            // ---- 下游把手里这对样本取走了 ----------------------------------
            // ★ 放在 case 之外、对所有状态生效：data 最后一个样本被锁存的那一拍
            //   也正好是 data 块结束、state 跳去 W_END 的那一拍，
            //   清零逻辑写在 W_DATA 里就会漏清。
            if (pcm_valid && pcm_ready) begin
                pcm_valid <= 1'b0;
                pcm_end   <= 1'b0;
            end

            // ---- 重新开始：单拍 start 在【任意状态】都可重启 -------------------
            // ★ start 必须是"全局"的：解析出错后停在 W_ERR，若只有 W_IDLE 认 start，
            //   控制器下一次发 start 会被丢掉，整条音频链就再也起不来。
            if (start) begin
                state          <= W_HDR;
                byte_cnt       <= 32'd0;
                hdr_idx        <= 4'd0;
                riff_r         <= 32'd0;
                riff_sz        <= 32'd0;
                wave_r         <= 32'd0;
                chunk_idx      <= 3'd0;
                cid            <= 32'd0;
                csz            <= 32'd0;
                fmt_idx        <= 5'd0;
                fmt_size       <= 32'd0;
                f_code         <= 16'd0;
                f_ch           <= 16'd0;
                f_rate         <= 32'd0;
                f_bits         <= 16'd0;
                fmt_seen       <= 1'b0;
                skip_cnt       <= 32'd0;
                pad_pend       <= 1'b0;
                dleft          <= 32'd0;
                phase          <= 2'd0;
                l_lo           <= 8'h00;
                l_hi           <= 8'h00;
                r_lo           <= 8'h00;
                wav_error      <= 1'b0;
                err_code       <= `ERR_NONE;
                err_detail     <= `DET_NONE;
                fallback_req   <= 1'b0;
                pcm_valid      <= 1'b0;
                pcm_end        <= 1'b0;
                samples_rd     <= 32'd0;
                track_id_o     <= track_id;
            end else begin
            case (state)
            // ------------------------------------------------------------------
            W_IDLE: ;   // 等 start（已在上面统一处理）
            // ---- 12 Byte RIFF 头：'RIFF' + size + 'WAVE' -------------------------
            W_HDR: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    case (hdr_idx)
                        4'd0, 4'd1, 4'd2, 4'd3 : riff_r  <= {din, riff_r[31:8]};
                        4'd4, 4'd5, 4'd6, 4'd7 : riff_sz <= {din, riff_sz[31:8]};
                        4'd8, 4'd9, 4'd10,4'd11: wave_r  <= {din, wave_r[31:8]};
                        default: ;
                    endcase

                    if (hdr_idx == 4'd11) begin
                        // riff_r 在 idx=3 已齐；wave 要用含本字节的装配值
                        if ((riff_r == ID_RIFF) && (wave_nxt == ID_WAVE)) begin
                            state     <= W_CHUNK;
                            chunk_idx <= 3'd0;
                        end else begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_RIFF;
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end
                    end else begin
                        hdr_idx <= hdr_idx + 4'd1;
                    end
                end
            end
            // ---- 8 Byte 块头：id + size，再分流到 fmt / data / 跳过 ---------------
            W_CHUNK: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    case (chunk_idx)
                        3'd0,3'd1,3'd2,3'd3 : cid <= {din, cid[31:8]};
                        3'd4,3'd5,3'd6,3'd7 : csz <= {din, csz[31:8]};
                        default: ;
                    endcase

                    if (chunk_idx == 3'd7) begin
                        // cid 在 idx=3 已齐；块大小用含本字节的 csz_nxt
                        if (cid == ID_FMT) begin
                            if (csz_nxt < 32'd16) begin
                                // fmt 块至少要 16 Byte（PCM 格式字段）
                                wav_error    <= 1'b1;
                                err_code     <= `ERR_WAV;
                                err_detail   <= `DET_WAV_RIFF;
                                fallback_req <= 1'b1;
                                state        <= W_ERR;
                            end else begin
                                state    <= W_FMT;
                                fmt_idx  <= 5'd0;
                                fmt_size <= csz_nxt;
                                f_code   <= 16'd0;
                                f_ch     <= 16'd0;
                                f_rate   <= 32'd0;
                                f_bits   <= 16'd0;
                            end
                        end else if (cid == ID_DATA) begin
                            if (!fmt_seen) begin
                                // data 在 fmt 之前 -> 容器结构错误
                                wav_error    <= 1'b1;
                                err_code     <= `ERR_WAV;
                                err_detail   <= `DET_WAV_RIFF;
                                fallback_req <= 1'b1;
                                state        <= W_ERR;
                            end else if ((file_size != 32'd0) &&
                                         ((byte_cnt + 32'd1 + csz_nxt) > file_size)) begin
                                // data 越界（声明长度装不下 PCM）
                                wav_error    <= 1'b1;
                                err_code     <= `ERR_WAV;
                                err_detail   <= `DET_WAV_RIFF;
                                fallback_req <= 1'b1;
                                state        <= W_ERR;
                            end else begin
                                data_size   <= csz_nxt;
                                // PCM 起始 = 本块头之后，即已消费字节数
                                data_offset <= byte_cnt + 32'd1;
                                dleft       <= csz_nxt;
                                phase       <= 2'd0;
                                state       <= W_DATA;
                            end
                        end else begin
                            // ★ 未知块（LIST / fact / cue ...）：按 chunk size 跳过
                            if (csz_nxt == 32'd0) begin
                                chunk_idx <= 3'd0;          // 空块：直接读下一个块头
                            end else begin
                                skip_cnt <= csz_nxt;
                                pad_pend <= csz_nxt[0];     // 奇数 size 需偶数对齐填充
                                state    <= W_SKIP;
                            end
                        end
                    end else begin
                        chunk_idx <= chunk_idx + 3'd1;
                    end
                end
            end
            // ---- fmt 块体：解析并校验（D-7）-------------------------------------
            W_FMT: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    case (fmt_idx)
                        5'd0, 5'd1           : f_code  <= {din, f_code[15:8]};
                        5'd2, 5'd3           : f_ch    <= {din, f_ch[15:8]};
                        5'd4, 5'd5, 5'd6, 5'd7  : f_rate <= {din, f_rate[31:8]};
                        5'd8, 5'd9, 5'd10,5'd11 : ;   // byte_rate：不校验
                        5'd12,5'd13          : ;   // block_align：不校验
                        5'd14,5'd15          : f_bits  <= {din, f_bits[15:8]};
                        default: ;
                    endcase

                    if ((fmt_idx + 5'd1) == fmt_size[4:0]) begin
                        // 本字节是 fmt 块的最后一个：字段已全部装配
                        header_done   <= 1'b1;
                        fmt_code      <= f_code;
                        num_channels  <= f_ch;
                        sample_rate   <= f_rate;
                        bits_per_sample <= bits_v;

                        if (f_code != 16'd1) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_PCM;    // 非 PCM
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else if (f_ch != 16'd2) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_FMT;    // 非立体声
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else if (f_rate != 32'd48000) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_RATE;   // 采样率非 48 kHz
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else if (bits_v != 16'd16) begin
                            wav_error    <= 1'b1;
                            err_code     <= `ERR_WAV;
                            err_detail   <= `DET_WAV_FMT;    // 非 16 bit
                            fallback_req <= 1'b1;
                            state        <= W_ERR;
                        end else begin
                            fmt_seen  <= 1'b1;
                            state     <= W_CHUNK;
                            chunk_idx <= 3'd0;
                        end
                    end else begin
                        fmt_idx <= fmt_idx + 5'd1;
                    end
                end
            end
            // ---- 未知块体：按 size 丢弃，奇数 size 再丢 1 Byte 对齐 ----------------
            W_SKIP: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    if (skip_cnt != 32'd0) begin
                        skip_cnt <= skip_cnt - 32'd1;
                        if ((skip_cnt == 32'd1) && !pad_pend) begin
                            state     <= W_CHUNK;
                            chunk_idx <= 3'd0;
                        end
                    end else if (pad_pend) begin
                        pad_pend <= 1'b0;
                        state    <= W_CHUNK;
                        chunk_idx <= 3'd0;
                    end
                end
            end
            // ---- data 块体：4 Byte -> 一对 16bit 样本 ---------------------------
            W_DATA: begin
                if (byte_taken) begin
                    byte_cnt <= byte_cnt + 32'd1;
                    dleft    <= dleft - 32'd1;
                    case (phase)
                        2'd0: begin l_lo <= din;             phase <= 2'd1; end
                        2'd1: begin l_hi <= din;             phase <= 2'd2; end
                        2'd2: begin r_lo <= din;             phase <= 2'd3; end
                        2'd3: begin
                            // 左声道先到（低 16 位），右声道后到（高 16 位）
                            pcm_l      <= {l_hi, l_lo};
                            pcm_r      <= {din, r_lo};
                            sample     <= {din, r_lo, l_hi, l_lo};
                            pcm_valid  <= 1'b1;
                            pcm_end    <= (dleft == 32'd1);   // 本字节即 data 末字节
                            samples_rd <= samples_rd + 32'd1;
                            phase      <= 2'd0;
                        end
                    endcase

                    if (dleft == 32'd1) begin
                        state <= W_END;
                    end
                end
            end
            // ------------------------------------------------------------------
            W_END: begin
                // 保持；下一次 start 从 W_IDLE 重新来
            end
            W_ERR: begin
                wav_error    <= 1'b1;
                fallback_req <= 1'b1;
            end
            default: state <= W_IDLE;
            endcase

            // ---- eof 边界检查：流提前结束（非 data 末字节）即容器不完整 ----------
            // ★ 放在 case 之后，最后一处赋值生效。din_ready 在 W_IDLE/W_END/W_ERR
            //   恒为 0，所以这里只可能命中 HDR/CHUNK/FMT/SKIP/DATA。
            if (byte_taken && din_eof &&
                !((state == W_DATA) && (dleft == 32'd1))) begin
                wav_error    <= 1'b1;
                err_code     <= `ERR_WAV;
                err_detail   <= `DET_WAV_RIFF;
                fallback_req <= 1'b1;
                state        <= W_ERR;
            end
            end     // else (start)
        end
    end

endmodule