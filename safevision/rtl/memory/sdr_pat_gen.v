


module sdr_pat_gen (
    input  wire [20:0] addr,
    input  wire [2:0]  mode,
    output reg  [31:0] pat
);


    wire [7:0] b0 = 8'hC3 ^ {addr[4:0], addr[7:5]};
    wire [7:0] b1 = 8'h3C ^ addr[7:0];
    wire [7:0] b2 = 8'h5A ^ addr[7:0] ^ addr[12:5];
    wire [7:0] b3 = 8'hA5 ^ addr[7:0] ^ addr[20:13];
    wire [31:0] p_addr = { b3, b2, b1, b0 };


    wire [31:0] x1 = { 11'b0, addr } + 32'hA5C3_5A3C;
    wire [31:0] x2 = x1 ^ (x1 << 13);
    wire [31:0] x3 = x2 ^ (x2 >> 17);
    wire [31:0] p_lfsr = x3 ^ (x3 << 5);


    wire [31:0] one = 32'd1 << addr[4:0];
    wire [31:0] p_w1 = one;
    wire [31:0] p_w0 = ~one;


    wire [31:0] p_alt = addr[0] ? 32'hFFFFFFFF : 32'h00000000;
    wire [31:0] p_adj = addr[0] ? 32'hAAAAAAAA : 32'h55555555;

    always @(*) begin
        case (mode)
            3'd0:    pat = p_addr;
            3'd1:    pat = p_lfsr;
            3'd2:    pat = p_w1;
            3'd3:    pat = p_w0;
            3'd4:    pat = p_alt;
            default: pat = p_adj;
        endcase
    end

endmodule
