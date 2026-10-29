


module control_event_queue #(
    parameter integer DEPTH    = 16,
    parameter integer AFULL_TH = 12
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire        push,
    input  wire [3:0]  push_type,
    input  wire [15:0] push_value,
    input  wire [31:0] push_ts,


    input  wire        pop,
    output wire [3:0]  out_type,
    output wire [15:0] out_value,
    output wire [31:0] out_ts,
    output wire        out_valid,
    output wire        empty,
    output wire        full,


    output reg  [15:0] ovf_cnt
);
    localparam integer EVT_W = 52;

    wire [EVT_W-1:0] head;
    wire [EVT_W-1:0] din = {push_ts, push_value, push_type};


    wire evt_wr = push & ~full;
    wire evt_rd = pop  & ~empty;

    sync_fifo #(
        .W               (EVT_W),
        .DEPTH           (DEPTH),
        .ALMOST_FULL_TH  (AFULL_TH),
        .ALMOST_EMPTY_TH (1)
    ) u_evt_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (evt_wr),
        .din          (din),
        .full         (full),
        .almost_full  (),
        .rd_en        (evt_rd),
        .dout         (head),
        .empty        (empty),
        .almost_empty (),
        .data_count   ()
    );

    assign out_valid = ~empty;
    assign out_type  = head[3:0];
    assign out_value = head[19:4];
    assign out_ts    = head[51:20];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ovf_cnt <= 16'd0;
        else if (push && full) ovf_cnt <= ovf_cnt + 16'd1;
    end

endmodule
