`include "pixel_format_defs.vh"


module frame_slot_commit(
    input wire clk,rst_n,frame_start,req_evt,mb_valid,mb_crc_ok,
    input wire [1:0] mb_slot,input wire [7:0] mb_generation,input wire mb_frame_index,
    output reg swap_ack_toggle,output reg active_valid,output reg [1:0] active_slot,
    output reg [7:0] generation,output reg frame_index,output wire [31:0] active_base,
    output wire [31:0] next_frame_base,output wire next_frame_valid,
    output reg commit,output reg invalid_payload
);
    reg capture_wait,pending;
    reg [1:0] pending_slot;reg [7:0] pending_generation;reg pending_index;
    assign active_base=`SV_SLOT_BASE(active_slot);
    assign next_frame_base=(frame_start&&pending)?`SV_SLOT_BASE(pending_slot):active_base;
    assign next_frame_valid=active_valid || (frame_start&&pending);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            capture_wait<=0;pending<=0;pending_slot<=0;pending_generation<=0;pending_index<=0;
            swap_ack_toggle<=0;active_valid<=0;active_slot<=0;generation<=0;frame_index<=0;
            commit<=0;invalid_payload<=0;
        end else begin
            commit<=0;invalid_payload<=0;
            if(req_evt)capture_wait<=1;
            if(capture_wait)begin
                capture_wait<=0;
                if(mb_valid&&mb_crc_ok)begin
                    pending_slot<=mb_slot;pending_generation<=mb_generation;
                    pending_index<=mb_frame_index;pending<=1;
                end else invalid_payload<=1;
            end
            if(frame_start&&pending)begin
                active_slot<=pending_slot;generation<=pending_generation;frame_index<=pending_index;
                active_valid<=1;swap_ack_toggle<=~swap_ack_toggle;pending<=0;commit<=1;
            end
        end
    end
endmodule
