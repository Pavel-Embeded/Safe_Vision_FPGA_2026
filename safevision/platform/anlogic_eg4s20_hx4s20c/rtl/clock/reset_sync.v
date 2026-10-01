// ============================================================================
// reset_sync.v — 单时钟域复位同步释放（SafeVision A · 板级时钟复位）
// ----------------------------------------------------------------------------
// 依据：手册 V2.0 §6.3/§10 与 docs/interface_spec.md「A 板级时钟复位接口」
//
// async_rst_n 拉低时，rst_n 不等待时钟立即拉低；恢复高电平后，必须经过
// RTL 中在 clk 的第 STAGES 个上升沿释放 rst_n，默认 STAGES=2，且须 >=2。
// 实物上异步源若靠近采样边沿，首级可能亚稳；释放时序仍须以 STA/板测核实。
// 每一个目标时钟域都要单独例化，不能把一个
// 域的同步释放结果直接送到另一个域。
// ============================================================================
module reset_sync #(
    parameter integer STAGES = 2
) (
    input  wire clk,
    input  wire async_rst_n,
    output wire rst_n
);

    reg [STAGES-1:0] release_pipe;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            release_pipe <= {STAGES{1'b0}};
        else
            release_pipe <= {release_pipe[STAGES-2:0], 1'b1};
    end

    assign rst_n = release_pipe[STAGES-1];

endmodule
