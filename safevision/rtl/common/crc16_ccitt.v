


module crc16_ccitt (
    input  wire [15:0] crc_in,
    input  wire [7:0]  data,
    output wire [15:0] crc_out
);

    function [15:0] step;
        input [15:0] c;
        input [7:0]  d;
        integer i;
        reg [15:0] t;
        begin
            t = c ^ {d, 8'h00};
            for (i = 0; i < 8; i = i + 1)
                t = t[15] ? ((t << 1) ^ 16'h1021) : (t << 1);
            step = t;
        end
    endfunction

    assign crc_out = step(crc_in, data);

endmodule
