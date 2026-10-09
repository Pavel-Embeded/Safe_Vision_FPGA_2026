// Pixel-domain media-fault display policy. All asynchronous inputs are levels;
// only their first synchronizer stages are excepted by board_cdc.sdc.
// The source selection is latched at vblank. A transient underflow keeps the
// safety scene for the following frame and recovers after one healthy frame.
// Boot and media faults do not reset video timing, the HDMI core or the PHY.
module board_display_guard (
    input wire pixel_clk,rst_n,frame_start,active_frame,frame_fault,
    input wire media_fault_async,storage_fault_async,manual_async,
    output reg safety_active,output reg [1:0] warning_level
);
    (* keep="true" *) reg media_meta,media_sync,storage_meta,storage_sync;
    (* keep="true" *) reg manual_meta,manual_sync;
    always @(posedge pixel_clk or negedge rst_n) begin
        if(!rst_n)begin
            media_meta<=0;media_sync<=0;storage_meta<=0;storage_sync<=0;
            manual_meta<=0;manual_sync<=0;safety_active<=1;warning_level<=0;
        end else begin
            media_meta<=media_fault_async;media_sync<=media_meta;
            storage_meta<=storage_fault_async;storage_sync<=storage_meta;
            manual_meta<=manual_async;manual_sync<=manual_meta;
            if(frame_start)begin
                safety_active<=!active_frame||frame_fault||media_sync||storage_sync||manual_sync;
                warning_level<=(frame_fault||media_sync||storage_sync)?2'd2:
                    (manual_sync?2'd1:2'd0);
            end
        end
    end
endmodule
