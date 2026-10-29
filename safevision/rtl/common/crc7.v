


module crc7 (
    input  wire [6:0] crc_in,
    input  wire [7:0] data,
    output wire [6:0] crc_out
);

    function [6:0] step;
        input [6:0] c;
        input [7:0] d;
        integer i;
        reg [6:0] t;
        begin
            t = c;
            for (i = 7; i >= 0; i = i - 1) begin
                if (t[6] ^ d[i])
                    t = (t << 1) ^ 7'h09;
                else
                    t = (t << 1);
            end
            step = t;
        end
    endfunction

    assign crc_out = step(crc_in, data);

endmodule
