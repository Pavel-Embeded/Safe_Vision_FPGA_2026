// Two-flop synchronization then consecutive-sample debounce.
// Default: 10 ms at 50 MHz. RESET_LEVEL is the logical idle level.
module a_debounce #(
    parameter integer STABLE_CYCLES=500000,
    parameter RESET_LEVEL=1'b0
)(input wire clk, input wire rst_n, input wire key_async,
  output reg key_level);
    function integer counter_width;
        input integer n;
        integer v;
        begin
            counter_width=1;
            for (v=n-1; v>1; v=v>>1) counter_width=counter_width+1;
        end
    endfunction
    localparam integer CW=counter_width(STABLE_CYCLES);
    (* ASYNC_REG = "TRUE" *) reg key_meta, key_sync;
    reg [CW-1:0] stable_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin key_meta<=RESET_LEVEL; key_sync<=RESET_LEVEL; end
        else begin key_meta<=key_async; key_sync<=key_meta; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin key_level<=RESET_LEVEL; stable_count<=0; end
        else if (key_sync == key_level) stable_count<=0;
        else if (stable_count == STABLE_CYCLES-1) begin
            key_level<=key_sync;
            stable_count<=0;
        end else stable_count<=stable_count+1'b1;
    end
    // synthesis translate_off
    initial if (STABLE_CYCLES<1 ||
        (RESET_LEVEL !== 1'b0 && RESET_LEVEL !== 1'b1))
        $fatal(1,"a_debounce invalid parameters");
    // synthesis translate_on
endmodule
