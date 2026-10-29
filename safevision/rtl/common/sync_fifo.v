


module sync_fifo #(
    parameter W                = 16,
    parameter DEPTH            = 64,
    parameter ALMOST_FULL_TH   = 48,
    parameter ALMOST_EMPTY_TH  = 4
)(
    input  wire            clk,
    input  wire            rst_n,


    input  wire            wr_en,
    input  wire [W-1:0]    din,
    output wire            full,
    output wire            almost_full,


    input  wire            rd_en,
    output wire [W-1:0]    dout,
    output wire            empty,
    output wire            almost_empty,


    output wire [$clog2(DEPTH):0] data_count
);

    localparam LOG2 = $clog2(DEPTH);


    reg [W-1:0]    mem [0:DEPTH-1];
    reg [LOG2-1:0] wr_ptr;
    reg [LOG2-1:0] rd_ptr;
    reg [LOG2:0]   cnt;

    wire wr_fire = wr_en & ~full;
    wire rd_fire = rd_en & ~empty;

    assign full         = (cnt == DEPTH);
    assign almost_full  = (cnt >= ALMOST_FULL_TH);
    assign empty        = (cnt == 0);
    assign almost_empty = (cnt <= ALMOST_EMPTY_TH);
    assign data_count   = cnt;


    assign dout = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {LOG2{1'b0}};
            rd_ptr <= {LOG2{1'b0}};
            cnt    <= {(LOG2+1){1'b0}};
        end else begin
            if (wr_fire) begin
                mem[wr_ptr] <= din;
                if (wr_ptr == DEPTH - 1) begin
                    wr_ptr <= {LOG2{1'b0}};
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            if (rd_fire) begin
                if (rd_ptr == DEPTH - 1) begin
                    rd_ptr <= {LOG2{1'b0}};
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end


            if (wr_fire && rd_fire) begin
                cnt <= cnt;
            end else if (wr_fire) begin
                cnt <= cnt + 1'b1;
            end else if (rd_fire) begin
                cnt <= cnt - 1'b1;
            end
        end
    end

endmodule
