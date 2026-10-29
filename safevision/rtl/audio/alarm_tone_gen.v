


module alarm_tone_gen #(
    parameter integer PHASE_INC = 1365,
    parameter integer AMP       = 2000000
)(
    input  wire        audio_clk,
    input  wire        rst_n,
    input  wire        tick,
    input  wire        enable,
    output wire [23:0] tone_l,
    output wire [23:0] tone_r
);

    reg [15:0] phase;
    wire [1:0] quad = phase[15:14];
    wire [4:0] qidx = phase[13:9];


    function signed [23:0] sin_q;
        input [4:0] i;
        begin
            case (i)
                5'd0:  sin_q = 24'sd0;
                5'd1:  sin_q = 24'sd98135;
                5'd2:  sin_q = 24'sd196034;
                5'd3:  sin_q = 24'sd293461;
                5'd4:  sin_q = 24'sd390181;
                5'd5:  sin_q = 24'sd485960;
                5'd6:  sin_q = 24'sd580569;
                5'd7:  sin_q = 24'sd673780;
                5'd8:  sin_q = 24'sd765367;
                5'd9:  sin_q = 24'sd855110;
                5'd10: sin_q = 24'sd942793;
                5'd11: sin_q = 24'sd1028205;
                5'd12: sin_q = 24'sd1111140;
                5'd13: sin_q = 24'sd1191399;
                5'd14: sin_q = 24'sd1268787;
                5'd15: sin_q = 24'sd1343118;
                5'd16: sin_q = 24'sd1414214;
                5'd17: sin_q = 24'sd1481902;
                5'd18: sin_q = 24'sd1546021;
                5'd19: sin_q = 24'sd1606415;
                5'd20: sin_q = 24'sd1662939;
                5'd21: sin_q = 24'sd1715457;
                5'd22: sin_q = 24'sd1763843;
                5'd23: sin_q = 24'sd1807979;
                5'd24: sin_q = 24'sd1847759;
                5'd25: sin_q = 24'sd1883088;
                5'd26: sin_q = 24'sd1913881;
                5'd27: sin_q = 24'sd1940063;
                5'd28: sin_q = 24'sd1961571;
                5'd29: sin_q = 24'sd1978353;
                5'd30: sin_q = 24'sd1990369;
                default: sin_q = 24'sd1997591;
            endcase
        end
    endfunction

    wire signed [23:0] idx_fwd = sin_q(qidx);
    wire signed [23:0] idx_rev = sin_q(5'd31 - qidx);
    wire signed [23:0] base = quad[0] ? idx_rev : idx_fwd;
    wire signed [23:0] val  = quad[1] ? -base : base;

    assign tone_l = val;
    assign tone_r = val;


    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 16'd0;
        end else if (!enable) begin
            phase <= 16'd0;
        end else if (tick) begin
            phase <= phase + PHASE_INC[15:0];
        end
    end

    // synthesis translate_off
    initial if (PHASE_INC < 1) begin $display("[FAIL] alarm_tone_gen invalid PHASE_INC (must be >= 1)"); $finish; end 
    // synthesis translate_on

endmodule
