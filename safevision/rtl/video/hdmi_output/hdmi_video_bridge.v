// Fixed-rate scan -> vendor AXIS, pixel domain. Geometry DE includes safe
// underflow pixels; pixel_valid must never gate the HDMI scan.
// Small queue preserves data/user/last during receiver backpressure. APUG092
// requires a continuous line and ready may drop AFTER accepted last only.
// Unexpected stalls are bounded by the queue. Overflow aborts the frame and
// resets the transmitter, then waits for the next SOF; it never pauses scan.
module hdmi_video_bridge #(
    parameter integer HD=0,QUEUE_AW=4
)(
    input wire clk,rst_n,de,input wire [11:0] x,y,input wire [23:0] rgb,
    output wire axis_valid,axis_user,axis_last,output wire [23:0] axis_data,
    input wire axis_ready,
    output reg resync,overflow_sticky,output reg [31:0] dropped_frames,
    output wire [QUEUE_AW:0] queue_level
);
    localparam integer DEPTH=1<<QUEUE_AW;
    reg [25:0] q[0:DEPTH-1];
    reg [QUEUE_AW-1:0] head,tail;reg [QUEUE_AW:0] count;
    reg wait_sof;
    wire sof=de&&(x==0)&&(y==0);
    wire pop=(count!=0)&&axis_ready;
    wire want=de&&(!wait_sof||sof);
    wire push=want&&((count<DEPTH)||pop);
    wire full_drop=want&&!push;
    assign queue_level=count;
    assign axis_valid=rst_n&&(count!=0);
    assign {axis_user,axis_last,axis_data}=q[head];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin head<=0;tail<=0;count<=0;wait_sof<=1;
            resync<=0;overflow_sticky<=0;dropped_frames<=0;end
        else begin
            resync<=0;
            if(full_drop)begin
                head<=0;tail<=0;count<=0;wait_sof<=1;resync<=1;
                overflow_sticky<=1;dropped_frames<=dropped_frames+1'b1;
            end else begin
                if(push)begin
                    q[tail]<={sof,(x==(HD?12'd1279:12'd639)),rgb};
                    tail<=tail+1'b1;wait_sof<=0;
                end
                if(pop)head<=head+1'b1;
                case({push,pop})2'b10:count<=count+1'b1;
                    2'b01:count<=count-1'b1;default:count<=count;endcase
            end
        end
    end
endmodule
