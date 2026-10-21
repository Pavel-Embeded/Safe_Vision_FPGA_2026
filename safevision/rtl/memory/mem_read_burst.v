// ============================================================================
// mem_read_burst.v — 读突发引擎（把 video_read_dma 的突发读变成 mem_ctrl 的逐字读）
// ----------------------------------------------------------------------------
// 为什么需要它（阶段 10 的真实教训）：
//   `memory_arbiter` 的读通道是按"ready 与 data_valid 同拍"的模型写的（它的 TB 里
//   那个内联 SDRAM 就是 `mem_ready=1` 且 `rd_data_valid = req && ready`）。而
//   `mem_ctrl` + `frame_memory_model` 是标准 valid/ready 语义：`ready`=可接收，
//   读数据晚 RD_LATENCY 拍才回。两者直接对接会**每 16 word 突发少收 1 拍数据**
//   （本工程实测：arbiter 发 16 次、只回 15 拍），读方永远等最后一个。
//   ⇒ 本模块用**一次只放 1 个在途请求**的保守时序，把"发地址"和"收数据"严格
//      配对，杜绝这种 off-by-one。
//
// 接口：上游是 video_read_dma 的 rd_* 突发口（req/addr/len -> ack/busy/data/valid），
//       下游是 mem_ctrl 的逐字事务口（mem_req/mem_addr -> mem_ready/mem_rdata*）。
//
// ★ 地址：mem_ctrl 要【逻辑字节地址】，本模块每 word +4（`sent << 2`，2 的幂用移位，
//   不用乘法/除法）。
// ============================================================================

module mem_read_burst (
    input  wire        clk,           // mem_clk
    input  wire        rst_n,

    // ---- 突发请求（来自 video_read_dma）----
    input  wire        req,
    input  wire [31:0] addr,          // 突发起始逻辑字节地址
    input  wire [15:0] len,           // 本次突发 word 数（0 视为 1）
    output reg         ack,           // 单拍：受理
    output wire        busy,          // 高：本突发进行中
    output reg  [31:0] data,          // 读回数据（单拍）
    output reg         data_valid,

    // ---- mem_ctrl 逐字事务口 ----
    output reg         mem_req,
    output reg  [31:0] mem_addr,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,
    input  wire        mem_rdata_valid
);

    localparam A_IDLE = 1'b0,
               A_RUN  = 1'b1;

    reg        state;
    reg [31:0] base;
    reg [15:0] total;
    reg [15:0] sent;        // 已发出的 word 请求数
    reg [15:0] got;         // 已收回的 word 数

    assign busy = (state == A_RUN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= A_IDLE;
            base       <= 32'd0;
            total      <= 16'd0;
            sent       <= 16'd0;
            got        <= 16'd0;
            ack        <= 1'b0;
            data       <= 32'd0;
            data_valid <= 1'b0;
            mem_req    <= 1'b0;
            mem_addr   <= 32'd0;
        end else begin
            // 默认单拍脉冲
            ack        <= 1'b0;
            data_valid <= 1'b0;

            case (state)
            A_IDLE: begin
                mem_req <= 1'b0;
                if (req) begin
                    ack     <= 1'b1;
                    base    <= addr;
                    total   <= (len == 16'd0) ? 16'd1 : len;
                    sent    <= 16'd0;
                    got     <= 16'd0;
                    state   <= A_RUN;
                end
            end
            // 一次只放 1 个在途请求：sent == got 时才发下一个
            A_RUN: begin
                mem_req  <= (sent < total) && (sent == got);
                mem_addr <= base + (sent << 2);

                if (mem_req && mem_ready) sent <= sent + 16'd1;

                if (mem_rdata_valid) begin
                    data       <= mem_rdata;
                    data_valid <= 1'b1;
                    got        <= got + 16'd1;
                end

                if (got == total) state <= A_IDLE;   // 本突发搬完
            end
            default: state <= A_IDLE;
            endcase
        end
    end

endmodule
