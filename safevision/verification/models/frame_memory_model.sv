


module frame_memory_model #(
    parameter integer ADDR_BITS   = 21,
    parameter integer INIT_CYCLES = 200,
    parameter integer RD_LATENCY  = 2
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire        req,
    input  wire        wr,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata,
    output reg         rdata_valid,
    output wire        ready,
    output reg         init_done
);


    localparam integer DEPTH = (1 << ADDR_BITS);
    reg [31:0] mem [0:DEPTH-1];


    localparam [1:0] S_INIT = 2'd0,
                     S_IDLE = 2'd1,
                     S_WR   = 2'd2,
                     S_RD   = 2'd3;

    reg [1:0] state;
    reg [7:0] init_cnt;
    reg [7:0] rd_cnt;
    reg [ADDR_BITS-1:0] rd_addr_q;


    assign ready = init_done && (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_INIT;
            init_cnt    <= 8'd0;
            rd_cnt      <= 8'd0;
            rd_addr_q   <= {ADDR_BITS{1'b0}};
            rdata       <= 32'd0;
            rdata_valid <= 1'b0;
            init_done   <= 1'b0;
        end else begin

            rdata_valid <= 1'b0;

            case (state)

                S_INIT: begin
                    if (init_cnt >= (INIT_CYCLES - 1)) begin
                        init_done <= 1'b1;
                        state     <= S_IDLE;
                    end else begin
                        init_cnt <= init_cnt + 8'd1;
                    end
                end


                S_IDLE: begin
                    if (req) begin
                        if (wr) begin

                            if (wstrb[0]) mem[addr[ADDR_BITS-1:0]][7:0]   <= wdata[7:0];
                            if (wstrb[1]) mem[addr[ADDR_BITS-1:0]][15:8]  <= wdata[15:8];
                            if (wstrb[2]) mem[addr[ADDR_BITS-1:0]][23:16] <= wdata[23:16];
                            if (wstrb[3]) mem[addr[ADDR_BITS-1:0]][31:24] <= wdata[31:24];
                            state <= S_WR;
                        end else begin
                            rd_addr_q <= addr[ADDR_BITS-1:0];
                            rd_cnt    <= RD_LATENCY;
                            state     <= S_RD;
                        end
                    end
                end


                S_WR: begin
                    state <= S_IDLE;
                end


                S_RD: begin
                    if (rd_cnt <= 8'd1) begin
                        rdata       <= mem[rd_addr_q];
                        rdata_valid <= 1'b1;
                        state       <= S_IDLE;
                    end else begin
                        rd_cnt <= rd_cnt - 8'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end


    task peek_word;
        input  [31:0] a;
        output [31:0] d;
        begin
            d = mem[a[ADDR_BITS-1:0]];
        end
    endtask

endmodule
