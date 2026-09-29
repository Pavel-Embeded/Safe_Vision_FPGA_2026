// ============================================================================
// rv_skid_buffer.v — 可反压流的时序切分缓冲（Register Slice + Skid Buffer）
// ----------------------------------------------------------------------------
// 文件职责：
//   在 valid/ready 字节流中间插入一级寄存器切分点，切断"上游 ready 到下游 ready"
//   的组合长路径；并额外提供一个"溢出寄存器"，让下游停顿的那一拍不至于立刻
//   回压到上游，从而吸收一个字节的时序余量。
//
// 依据：
//   本工程自定：可反压流的时序切分缓冲（Register Slice + Skid Buffer）
//   手册 7.7 / docs/interface_spec.md §一「全链公共约定」：
//     「握手 valid / ready；ready 为低时发送方必须保持 data 不变」
//   同节 CDC 约定：控制类单比特用 toggle，禁止单拍脉冲跨域——本模块是【同域】
//   时序件，不做任何跨域，只做时序切分。
//
// 关键设计决策：
//   1) in_ready 只由 skid_valid 这一个寄存器译出（in_ready = ~s_valid）。
//      这样 out_ready → in_ready 之间【没有任何组合路径】，切分点才真正成立；
//      若写成 (~s_valid | out_ready) 之类的组合式，切分点立刻失效。
//   2) 主寄存器 B 直接驱动 out_valid / out_data；溢出寄存器 S 只在
//      "B 有效且下游未取走"这一拍才装载，所以下游反压期间 out_data 绝对不变。
//   3) 下游始终 ready 时 S 恒空，流水线无气泡，吞吐 = 1 字节/拍。
//
// 实测踩过的坑（写联调代码时留意）：
//   - 上游必须遵守 in_valid && !in_ready 时 in_data 保持不变；反压期间随手改
//     in_data 会让本模块把错数据锁进 S。这与 sd_sector_reader 那条约定的道理一样。
//   - out_valid && !out_ready 时下游不得取数；本模块只是"保证数据不变"，
//     并不能替下游纠正非法消费。
// ============================================================================

module rv_skid_buffer #(
    parameter W = 8
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [W-1:0] in_data,
    input  wire         in_valid,
    output wire         in_ready,

    output wire [W-1:0] out_data,
    output wire         out_valid,
    input  wire         out_ready
);

    // ---- 主寄存器 B：直接驱动输出 ----
    reg [W-1:0] b_data;
    reg         b_valid;

    // ---- 溢出寄存器 S：只在 B 被占住且下游停顿时装一个字节 ----
    reg [W-1:0] s_data;
    reg         s_valid;

    wire b_fire  = b_valid & out_ready;     // 本拍下游取走 B
    wire in_fire = in_valid & in_ready;     // 本拍上游被接收

    // ★ 只由寄存器译出，切断组合长路径
    assign in_ready  = ~s_valid;
    assign out_data  = b_data;
    assign out_valid = b_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_data  <= {W{1'b0}};
            b_valid <= 1'b0;
            s_data  <= {W{1'b0}};
            s_valid <= 1'b0;
        end else begin
            // ------------------------------------------------------------------
            // 主寄存器 B 的更新
            // ------------------------------------------------------------------
            if (b_fire) begin
                // 下游本拍取走了 B：立刻从 S 补充，否则从输入端补充
                if (s_valid) begin
                    b_data  <= s_data;
                    b_valid <= 1'b1;
                end else if (in_fire) begin
                    b_data  <= in_data;
                    b_valid <= 1'b1;
                end else begin
                    b_valid <= 1'b0;
                end
            end else if (!b_valid) begin
                // B 空且下游没取：从输入端或 S 装一个字
                if (in_fire) begin
                    b_data  <= in_data;
                    b_valid <= 1'b1;
                end else if (s_valid) begin
                    b_data  <= s_data;
                    b_valid <= 1'b1;
                end
            end
            // else：B 有效且下游未取走 —— 保持不动（这就是"反压时 data 不变"）

            // ------------------------------------------------------------------
            // 溢出寄存器 S 的更新
            // ------------------------------------------------------------------
            if (b_fire) begin
                if (s_valid) begin
                    // S 本拍被搬进 B，空出来后可以接收新字节
                    if (in_fire) begin
                        s_data  <= in_data;
                        s_valid <= 1'b1;
                    end else begin
                        s_valid <= 1'b0;
                    end
                end else begin
                    s_valid <= 1'b0;
                end
            end else if (b_valid) begin
                // B 被占住且下游没取：把上游新字节寄存进 S（吸收一拍）
                if (in_fire) begin
                    s_data  <= in_data;
                    s_valid <= 1'b1;
                end
            end else begin
                // B 空：S 本拍被搬进 B（或本来就空），清掉
                s_valid <= 1'b0;
            end
        end
    end

endmodule