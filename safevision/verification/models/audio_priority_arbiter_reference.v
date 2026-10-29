


module audio_priority_arbiter_reference #(
    parameter integer RAMP_N     = 240,
    parameter integer FULL_SCALE = 256
)(
    input  wire        audio_clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire        alarm_req,
    input  wire [23:0] wav_l,
    input  wire [23:0] wav_r,
    input  wire [23:0] tone_l,
    input  wire [23:0] tone_r,
    output reg  [23:0] audio_l,
    output reg  [23:0] audio_r,
    output reg         audio_valid,
    output reg  [8:0]  gain
);


    reg [31:0] ramp_error;
    wire [32:0] ramp_sum={1'b0,ramp_error}+FULL_SCALE;
    wire [8:0] ramp_step=ramp_sum/RAMP_N;
    wire [8:0] gain_up = (gain + ramp_step > 9'd256)  ?  9'd256 : (gain + ramp_step);
    wire [8:0] gain_dn = (gain > ramp_step)  ?  (gain - ramp_step) : 9'd0;
    wire [8:0] n_gain  = alarm_req  ?  gain_up : gain_dn;
    wire [8:0] w_coef  = 9'd256 - n_gain;

    wire signed [23:0] wl_s = wav_l;
    wire signed [23:0] wr_s = wav_r;
    wire signed [23:0] tl_s = tone_l;
    wire signed [23:0] tr_s = tone_r;

    wire signed [33:0] mix_l = wl_s * $signed({1'b0, w_coef}) + tl_s * $signed({1'b0, n_gain});
    wire signed [33:0] mix_r = wr_s * $signed({1'b0, w_coef}) + tr_s * $signed({1'b0, n_gain});

    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            gain        <= 9'd0; ramp_error<=0;
            audio_l     <= 24'sd0;
            audio_r     <= 24'sd0;
            audio_valid <= 1'b0;
        end else if (sample_valid) begin
            gain        <= n_gain; ramp_error<=ramp_sum%RAMP_N;
            audio_l     <= mix_l[31:8];
            audio_r     <= mix_r[31:8];
            audio_valid <= 1'b1;
        end else begin
            audio_valid <= 1'b0;
        end
    end

    // synthesis translate_off
    initial if (FULL_SCALE != 256 || RAMP_N<1)
        begin $display("[FAIL] audio_priority_arbiter invalid FULL_SCALE (must be 256, RAMP_N >= 1)"); $finish; end 
    // synthesis translate_on

endmodule
