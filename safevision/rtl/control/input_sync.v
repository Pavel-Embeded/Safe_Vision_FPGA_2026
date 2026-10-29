


module input_sync #(
    parameter integer USE_TICK=0,
    parameter integer DEB_N       = 2000000,
    parameter         RESET_LEVEL = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tick,
    input  wire async_in,
    input  wire evt_clear,
    output reg  press,
    output reg  level,
    output reg  evt_pending
);

    function integer counter_width;
        input integer n;
        integer v;
        begin
            counter_width = 1;
            for (v = n-1; v > 1; v = v >> 1) counter_width = counter_width + 1;
        end
    endfunction
    localparam integer CW = counter_width(DEB_N);

    (* ASYNC_REG = "TRUE" *) reg sync_meta;
    (* ASYNC_REG = "TRUE" *) reg sync_sync;
    reg level_d;
    reg [CW-1:0] db_cnt;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync_meta <= RESET_LEVEL; sync_sync <= RESET_LEVEL; end
        else begin sync_meta <= async_in; sync_sync <= sync_meta; end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level <= RESET_LEVEL; level_d <= RESET_LEVEL; db_cnt <= 0; press <= 1'b0;
        end else begin
            level_d <= level;
            press   <= level & ~level_d;
            if (sync_sync != level) begin
                if(!USE_TICK||tick)begin
                if (db_cnt == DEB_N-1) begin level <= sync_sync; db_cnt <= 0; end
                else db_cnt <= db_cnt + 1'b1;
                end
            end else db_cnt <= 0;
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) evt_pending <= 1'b0;
        else if (press)     evt_pending <= 1'b1;
        else if (evt_clear) evt_pending <= 1'b0;
    end

    // synthesis translate_off
    initial if (DEB_N < 1) $fatal(1, "input_sync invalid DEB_N (must be >= 1)");
    // synthesis translate_on

endmodule
