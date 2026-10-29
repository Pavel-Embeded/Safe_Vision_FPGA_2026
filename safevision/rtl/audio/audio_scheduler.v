


module audio_scheduler #(
    parameter integer TICK_N = 255
)(
    input  wire        audio_clk,
    input  wire        rst_n,


    input  wire [15:0] pcm_l,
    input  wire [15:0] pcm_r,
    input  wire        pcm_valid,
    input  wire        pcm_empty,
    output reg         pcm_rd,
    input  wire        audio_fallback,
    input  wire [7:0]  track_id_in,
    input  wire        track_change,


    output reg  [23:0] audio_l,
    output reg  [23:0] audio_r,
    output reg         audio_valid,
    output reg  [7:0]  track_id,
    output reg  [31:0] audio_underflow,


    output reg         sample_tick
);

    reg [15:0] tcnt;


    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            tcnt        <= 16'd0;
            sample_tick <= 1'b0;
        end else if (tcnt == TICK_N[15:0]) begin
            tcnt        <= 16'd0;
            sample_tick <= 1'b1;
        end else begin
            tcnt        <= tcnt + 16'd1;
            sample_tick <= 1'b0;
        end
    end


    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            audio_l         <= 24'sd0;
            audio_r         <= 24'sd0;
            audio_valid     <= 1'b0;
            pcm_rd          <= 1'b0;
            track_id        <= 8'h00;
            audio_underflow <= 32'd0;
        end else begin
            pcm_rd      <= 1'b0;
            audio_valid <= 1'b0;
            if (sample_tick) begin
                track_id <= track_id_in;
                if (pcm_empty) begin

                    audio_l         <= 24'sd0;
                    audio_r         <= 24'sd0;
                    audio_underflow <= audio_underflow + 32'd1;
                end else begin

                    audio_l <= {{8{pcm_l[15]}}, pcm_l};
                    audio_r <= {{8{pcm_r[15]}}, pcm_r};
                    pcm_rd  <= 1'b1;
                end
                audio_valid <= 1'b1;
            end
        end
    end

    // synthesis translate_off
    initial if (TICK_N < 1) begin $display("[FAIL] audio_scheduler invalid TICK_N (must be >= 1)"); $finish; end 
    // synthesis translate_on

endmodule
