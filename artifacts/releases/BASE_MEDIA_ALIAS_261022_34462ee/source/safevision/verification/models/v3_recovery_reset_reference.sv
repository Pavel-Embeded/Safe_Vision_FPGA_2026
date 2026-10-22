// SYS controller survives media reset. Reset is finite, then rescan is started.
// Failure/timeout keeps SAFE; a new manual request is required for another try.
module v3_recovery_reset_reference #(
    parameter integer RESET_CYCLES=32, SETTLE_CYCLES=32,
    parameter integer TIMEOUT_CYCLES=500000000, MAX_ATTEMPTS=3
)(
    input wire clk,rst_n,request,done,failed,fatal,
    output wire busy,media_reset,output reg rescan_start,recovered,
    output reg safe_latched,output reg [1:0] attempts,
    output reg [2:0] state
);
    localparam IDLE=0,RESET=1,SETTLE=2,START=3,WAIT=4,LOCKED=5;
    reg [31:0] timer;
    assign busy=(state!=IDLE && state!=LOCKED);
    assign media_reset=(state==RESET);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;timer<=0;rescan_start<=0;recovered<=0;
            safe_latched<=0;attempts<=0;
        end else begin
            rescan_start<=0;recovered<=0;
            if(fatal) begin state<=LOCKED;safe_latched<=1;end
            else case(state)
                IDLE,LOCKED: if(request && attempts<MAX_ATTEMPTS) begin
                    attempts<=attempts+1'b1;safe_latched<=1;timer<=0;state<=RESET;
                end
                RESET: if(timer==RESET_CYCLES-1)begin timer<=0;state<=SETTLE;end
                       else timer<=timer+1'b1;
                SETTLE: if(timer==SETTLE_CYCLES-1)begin timer<=0;state<=START;end
                        else timer<=timer+1'b1;
                START:begin rescan_start<=1;timer<=0;state<=WAIT;end
                WAIT: if(failed || timer>=TIMEOUT_CYCLES-1)begin state<=LOCKED;end
                      else if(done)begin
                          state<=IDLE;safe_latched<=0;attempts<=0;recovered<=1;
                      end else timer<=timer+1'b1;
                default:begin state<=LOCKED;safe_latched<=1;end
            endcase
        end
    end
    // synthesis translate_off
    initial if(RESET_CYCLES<2 || SETTLE_CYCLES<2 || MAX_ATTEMPTS>3 || TIMEOUT_CYCLES<1)
        $fatal(1,"invalid media recovery parameters");
    // synthesis translate_on
endmodule
