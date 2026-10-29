


`include "fault_code_defs.vh"

module emergency_fsm (
    clk, rst_n,
    fire_in, alarm_in, media_fault, media_ok, fault_code_in, fatal,
    confirm, confirm_stable, recover_ack, media_selftest_ok,
    direction_in, direction_valid, warn_window_done, info_only,
    commit_ack_toggle,
    emergency_active, warning_level, direction, alarm_enable, fault_reason,
    commit_toggle, state, bram_req
);
    input  wire       clk;
    input  wire       rst_n;


    input  wire       fire_in;
    input  wire       alarm_in;
    input  wire       media_fault;
    input  wire       media_ok;
    input  wire [7:0] fault_code_in;
    input  wire       fatal;
    input  wire       confirm;
    input  wire       confirm_stable;
    input  wire       recover_ack;
    input  wire       media_selftest_ok;
    input  wire [1:0] direction_in;
    input  wire       direction_valid;
    input  wire       warn_window_done;
    input  wire       info_only;
    input  wire       commit_ack_toggle;


    output reg        emergency_active;
    output reg  [1:0] warning_level;
    output reg  [1:0] direction;
    output reg        alarm_enable;
    output reg  [7:0] fault_reason;
    output reg        commit_toggle;


    output reg  [2:0] state;
    output wire       bram_req;

    localparam [2:0] S_NORMAL     = 3'd0;
    localparam [2:0] S_WARNING    = 3'd1;
    localparam [2:0] S_EMERGENCY  = 3'd2;
    localparam [2:0] S_EVACUATION = 3'd3;
    localparam [2:0] S_FAIL_SAFE  = 3'd4;

    reg        evt_fire;
    reg [7:0]  reason_latch;
    reg [1:0]  dir_hold;

    wire       fire_evt = fire_in | alarm_in;
    wire [1:0] dir_in_c = (direction_in == 2'd3) ? 2'd2 : direction_in;
    wire       dir_chg  = direction_valid & (dir_in_c != dir_hold);

    assign bram_req = (state == S_FAIL_SAFE);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_NORMAL;
            evt_fire     <= 1'b0;
            reason_latch <= `ERR_NONE;
            dir_hold     <= 2'd0;
        end else begin

            if (media_fault && reason_latch == `ERR_NONE)
                reason_latch <= fault_code_in;

            case (state)
                S_NORMAL: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (fire_evt) begin
                        evt_fire <= 1'b1;
                        dir_hold <= direction_valid ? dir_in_c : 2'd0;
                        state    <= S_EMERGENCY;
                    end else if (media_fault && !media_ok) begin
                        state <= S_FAIL_SAFE;
                    end else if (media_fault && media_ok) begin
                        state <= S_WARNING;
                    end
                end

                S_WARNING: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (fire_evt) begin
                        evt_fire <= 1'b1;
                        dir_hold <= direction_valid ? dir_in_c : 2'd0;
                        state    <= S_EMERGENCY;
                    end else if (media_fault && !media_ok) begin
                        state <= S_FAIL_SAFE;
                    end else if (!media_fault && warn_window_done) begin
                        reason_latch <= `ERR_NONE;
                        state <= S_NORMAL;
                    end
                end

                S_EMERGENCY: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (evt_fire && direction_valid) begin
                        dir_hold <= dir_in_c;
                        state    <= S_EVACUATION;
                    end else if (dir_chg) begin
                        dir_hold <= dir_in_c;
                    end

                end

                S_EVACUATION: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (media_fault && !media_ok) begin
                        state <= S_FAIL_SAFE;
                    end else if (dir_chg) begin
                        dir_hold <= dir_in_c;
                    end else if (confirm && confirm_stable) begin
                        evt_fire     <= 1'b0;
                        reason_latch <= `ERR_NONE;
                        dir_hold     <= 2'd0;
                        state        <= S_NORMAL;
                    end
                end

                S_FAIL_SAFE: begin
                    if (recover_ack && media_selftest_ok && !fatal) begin
                        reason_latch <= `ERR_NONE;
                        evt_fire     <= 1'b0;
                        dir_hold     <= 2'd0;
                        state        <= S_NORMAL;
                    end

                end

                default: state <= S_NORMAL;
            endcase
        end
    end


    reg       n_active;
    reg [1:0] n_level;
    reg [1:0] n_dir;
    reg       n_alarm;
    reg [7:0] n_reason;
    always @* begin
        n_active = 1'b0; n_level = 2'd0; n_dir = 2'd0; n_alarm = 1'b0;
        n_reason = reason_latch;
        case (state)
            S_NORMAL: begin
                n_active = 1'b0; n_level = 2'd0; n_dir = 2'd0;
                n_alarm  = info_only;
            end
            S_WARNING: begin
                n_active = 1'b1; n_level = 2'd1; n_dir = 2'd0; n_alarm = 1'b1;
            end
            S_EMERGENCY: begin
                n_active = 1'b1; n_level = 2'd2; n_dir = dir_hold; n_alarm = evt_fire;
            end
            S_EVACUATION: begin
                n_active = 1'b1; n_level = 2'd2; n_dir = dir_hold; n_alarm = evt_fire;
            end
            S_FAIL_SAFE: begin
                n_active = 1'b1; n_level = 2'd2; n_dir = 2'd1; n_alarm = 1'b1;
                n_reason = (reason_latch == `ERR_NONE) ? `ERR_MEDIA_INVALID : reason_latch;
            end
            default: begin
                n_active = 1'b0; n_level = 2'd0; n_dir = 2'd0; n_alarm = 1'b0;
            end
        endcase
    end


    wire        acked = (commit_ack_toggle == commit_toggle);
    wire [13:0] n_pay = {n_active, n_level, n_dir, n_alarm, n_reason};
    wire [13:0] c_pay = {emergency_active, warning_level, direction, alarm_enable, fault_reason};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            emergency_active <= 1'b0;
            warning_level    <= 2'd0;
            direction        <= 2'd0;
            alarm_enable     <= 1'b0;
            fault_reason     <= `ERR_NONE;
            commit_toggle    <= 1'b0;
        end else if (acked && (n_pay != c_pay)) begin
            emergency_active <= n_active;
            warning_level    <= n_level;
            direction        <= n_dir;
            alarm_enable     <= n_alarm;
            fault_reason     <= n_reason;
            commit_toggle    <= ~commit_toggle;
        end
    end

endmodule
