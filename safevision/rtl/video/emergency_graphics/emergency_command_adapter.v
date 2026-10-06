// Optional C native SYS-domain commit_toggle -> A valid/ready adapter.
// C keeps all five payload bits unchanged until commit_ack_toggle equals its
// commit_toggle, and cannot commit again before that ACK. Both endpoints reset
// their toggles to zero in the same SYS reset epoch. This is NOT an async CDC;
// emergency_control_bridge performs the atomic SYS -> PIXEL crossing.
module emergency_command_adapter(
    input wire clk,rst_n,commit_toggle,emergency_active,
    input wire [1:0] direction,warning_level,
    output reg commit_ack_toggle,
    output reg ctrl_valid,input wire ctrl_ready,
    output reg ctrl_active,output reg [1:0] ctrl_direction,ctrl_level
);
    reg seen,saved_toggle;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            seen<=0;saved_toggle<=0;commit_ack_toggle<=0;ctrl_valid<=0;
            ctrl_active<=0;ctrl_direction<=0;ctrl_level<=0;
        end else begin
            if(ctrl_valid&&ctrl_ready)begin
                ctrl_valid<=0;commit_ack_toggle<=saved_toggle;
            end
            if((!ctrl_valid||ctrl_ready)&&commit_toggle!=seen)begin
                ctrl_valid<=1;seen<=commit_toggle;saved_toggle<=commit_toggle;
                ctrl_active<=emergency_active;ctrl_direction<=direction;ctrl_level<=warning_level;
            end
        end
    end
endmodule
