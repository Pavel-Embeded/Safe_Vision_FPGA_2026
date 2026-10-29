


module mem_read_burst (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        req,
    input  wire [31:0] addr,
    input  wire [15:0] len,
    output reg         ack,
    output wire        busy,
    output reg  [31:0] data,
    output reg         data_valid,


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
    reg [15:0] sent;
    reg [15:0] got;

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

            A_RUN: begin
                mem_req  <= (sent < total) && (sent == got);
                mem_addr <= base + (sent << 2);

                if (mem_req && mem_ready) sent <= sent + 16'd1;

                if (mem_rdata_valid) begin
                    data       <= mem_rdata;
                    data_valid <= 1'b1;
                    got        <= got + 16'd1;
                end

                if (got == total) state <= A_IDLE;
            end
            default: state <= A_IDLE;
            endcase
        end
    end

endmodule
