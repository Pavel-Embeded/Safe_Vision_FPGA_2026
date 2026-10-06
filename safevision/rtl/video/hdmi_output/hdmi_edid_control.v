// Synchronize optional physical HPD. If the board exposes no FPGA HPD pin,
// tie hpd=1 and use reread (PIXEL synchronous) for an explicit EDID retry.
module hdmi_edid_control #(parameter integer SETTLE_CYCLES=100000)(
    input wire clk,rst_n,hpd,reread,
    output reg trigger,output wire connected,output wire tx_reset
);
    (* async_reg="true" *) reg hpd_meta,hpd_sync;
    reg last_hpd,last_reread,pending;
    localparam integer CW=SETTLE_CYCLES<2?1:$clog2(SETTLE_CYCLES);
    reg [CW-1:0] count;
    assign connected=hpd_sync;
    assign tx_reset=!rst_n||!hpd_sync;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin hpd_meta<=0;hpd_sync<=0;last_hpd<=0;
            last_reread<=0;pending<=0;count<=0;trigger<=0;end
        else begin
            hpd_meta<=hpd;hpd_sync<=hpd_meta;last_hpd<=hpd_sync;
            last_reread<=reread;trigger<=0;
            if(!hpd_sync)begin pending<=0;count<=0;end
            else if(!last_hpd||(reread&&!last_reread))begin pending<=1;count<=0;end
            else if(pending)begin
                if(count>=SETTLE_CYCLES-1)begin trigger<=1;pending<=0;end
                else count<=count+1'b1;
            end
        end
    end
endmodule
