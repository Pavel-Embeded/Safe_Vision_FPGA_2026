// Stage-1 modules genuinely instantiated for synthesis/internal STA at 50 MHz.
module a_basics_verify_top(input wire board_clk,board_rst_n,key_async,
    input wire start,warning,emergency,clear,enable,
    output wire [14:0] probe);
    wire rst_n,level,rise,fall,tick;wire [1:0] mode;wire [9:0] count;
    reset_sync reset(.clk(board_clk),.async_rst_n(board_rst_n),.rst_n(rst_n));
    a_counter counter(.clk(board_clk),.rst_n(rst_n),.enable(enable),.count(count),.tick(tick));
    a_debounce key(.clk(board_clk),.rst_n(rst_n),.key_async(key_async),.key_level(level));
    a_edge_detect edge_events(.clk(board_clk),.rst_n(rst_n),.sig(level),.rise(rise),.fall(fall));
    a_mode_fsm mode_demo(.clk(board_clk),.rst_n(rst_n),.start(start),.warning(warning),
        .emergency(emergency),.clear(clear),.mode(mode));
    assign probe={count,tick,rise,fall,mode};
endmodule
