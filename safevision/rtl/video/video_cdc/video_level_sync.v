
module video_level_sync #(parameter RESET_VALUE=1'b0)(
    input wire clk,rst_n,async_level,output wire level
);
    (* async_reg="true", keep="true" *) reg meta,synced;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin meta<=RESET_VALUE;synced<=RESET_VALUE;end
        else begin meta<=async_level;synced<=meta;end
    end
    assign level=synced;
endmodule
