


module emergency_control_bridge #(parameter integer IMMEDIATE=0)(
    input wire sys_clk,sys_rst_n,pixel_clk,pixel_rst_n,
    input wire ctrl_valid,output wire ctrl_ready,
    input wire emergency_active,input wire [1:0] direction,warning_level,
    input wire frame_start,
    output reg active,output reg [1:0] active_direction,active_level,
    output reg applied,output wire pending_o
);
    wire [4:0] message;
    wire valid,ready;
    reg pending;reg [4:0] saved;
    assign pending_o=pending||valid;
    assign ready=(IMMEDIATE!=0)||!pending||frame_start;
    video_cdc_mailbox #(.WIDTH(5)) mailbox(
        .src_clk(sys_clk),.src_rst_n(sys_rst_n),
        .src_data({emergency_active,direction,warning_level}),
        .src_valid(ctrl_valid),.src_ready(ctrl_ready),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),
        .dst_data(message),.dst_valid(valid),.dst_ready(ready));
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin
            active<=0;active_direction<=0;active_level<=0;applied<=0;
            pending<=0;saved<=0;
        end else begin
            applied<=0;
            if(IMMEDIATE!=0)begin
                if(valid)begin
                    {active,active_direction,active_level}<=message;
                    applied<=1;
                end
            end else begin
                if(frame_start&&pending)begin
                    {active,active_direction,active_level}<=saved;
                    applied<=1;pending<=0;
                end
                if(valid&&ready)begin
                    if(frame_start&&!pending)begin
                        {active,active_direction,active_level}<=message;
                        applied<=1;
                    end else begin saved<=message;pending<=1;end
                end
            end
        end
    end
endmodule
