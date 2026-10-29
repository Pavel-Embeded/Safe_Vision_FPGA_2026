


module key_debounce (
    clk, rst_n, key_async, evt_clear, tick,
    key_level, press_vec, press_any, evt_key, evt_pending
);
    parameter integer USE_TICK=0;
    parameter integer KEYS        = 4;
    parameter integer DEB_N       = 2000000;
    parameter         RESET_LEVEL = 1'b0;

    function integer clog2;
        input integer n;
        integer v;
        begin
            clog2 = 1;
            for (v = n-1; v > 1; v = v >> 1) clog2 = clog2 + 1;
        end
    endfunction
    localparam integer KW = clog2(KEYS);

    input wire tick;
    input  wire            clk;
    input  wire            rst_n;
    input  wire [KEYS-1:0] key_async;
    input  wire            evt_clear;
    output wire [KEYS-1:0] key_level;
    output wire [KEYS-1:0] press_vec;
    output wire            press_any;
    output reg  [KW-1:0]   evt_key;
    output reg             evt_pending;

    genvar g;
    generate
        for (g = 0; g < KEYS; g = g + 1) begin : g_key
            input_sync #(
                .USE_TICK(USE_TICK),.DEB_N       (DEB_N),
                .RESET_LEVEL (RESET_LEVEL)
            ) u_ch (
                .tick(tick),.clk         (clk),
                .rst_n       (rst_n),
                .async_in    (key_async[g]),
                .evt_clear   (evt_clear),
                .press       (press_vec[g]),
                .level       (key_level[g]),
                .evt_pending (                               )
            );
        end
    endgenerate


    integer i;
    reg [KW-1:0] key_sel;
    always @* begin
        key_sel = {KW{1'b0}};
        for (i = KEYS-1; i >= 0; i = i - 1)
            if (press_vec[i]) key_sel = i[KW-1:0];
    end

    assign press_any = |press_vec;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            evt_key <= {KW{1'b0}};
            evt_pending <= 1'b0;
        end else if (press_any) begin
            evt_key <= key_sel;
            evt_pending <= 1'b1;
        end else if (evt_clear) begin
            evt_pending <= 1'b0;
        end
    end

endmodule
