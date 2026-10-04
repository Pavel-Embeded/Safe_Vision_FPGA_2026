// Stage 1 demonstration ONLY, not C's safety controller.
// Requests are synchronous. Emergency > warning > clear > start.
// WARNING/EMERGENCY latch until clear with both fault inputs low.
module a_mode_fsm(input wire clk, input wire rst_n,
    input wire start, input wire warning, input wire emergency, input wire clear,
    output reg [1:0] mode);
    localparam IDLE=2'd0, NORMAL=2'd1, WARNING=2'd2, EMERGENCY=2'd3;
    reg [1:0] next_mode;
    always @* begin
        next_mode=mode;
        case (mode)
            IDLE: if (start) next_mode=NORMAL;
            NORMAL: next_mode=NORMAL;
            WARNING: next_mode=WARNING;
            EMERGENCY: next_mode=EMERGENCY;
            default: next_mode=IDLE;
        endcase
        if (clear && !warning && !emergency) next_mode=IDLE;
        if (warning && mode != EMERGENCY) next_mode=WARNING;
        if (emergency) next_mode=EMERGENCY;
    end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) mode<=IDLE;
        else mode<=next_mode;
endmodule
