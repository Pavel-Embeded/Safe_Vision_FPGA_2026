


module mem_ctrl #(


    parameter [31:0] TO_MEM = 32'd4096
)(
    input  wire        clk,
    input  wire        rst_n,


    output wire        init_done,
    input  wire        req,
    input  wire        wr,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output wire [31:0] rdata,
    output wire        rdata_valid,
    output wire        ready,
    output wire        mem_error,


    output wire        sdram_req,
    output wire        sdram_wr,
    output wire [31:0] sdram_addr,
    output wire [31:0] sdram_wdata,
    output wire [3:0]  sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_rdata_valid,
    input  wire        sdram_ready,
    input  wire        sdram_init_done
);


    assign sdram_addr = {2'b00, addr[31:2]};

    assign init_done      = sdram_init_done;
    assign sdram_req      = req;
    assign sdram_wr       = wr;
    assign sdram_wdata    = wdata;
    assign sdram_wstrb    = wstrb;

    assign rdata          = sdram_rdata;
    assign rdata_valid    = sdram_rdata_valid;
    assign ready          = sdram_ready;


    reg [31:0] to_cnt;
    reg        mem_error_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            to_cnt      <= 32'd0;
            mem_error_r <= 1'b0;
        end else begin
            if (req && !sdram_ready) begin
                if (to_cnt >= TO_MEM) mem_error_r <= 1'b1;
                else                  to_cnt     <= to_cnt + 32'd1;
            end else begin
                to_cnt <= 32'd0;
            end
        end
    end

    assign mem_error = mem_error_r;

endmodule
