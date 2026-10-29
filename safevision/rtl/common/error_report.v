


module error_report (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        err_push,
    input  wire [7:0]  err_code,
    input  wire [3:0]  err_src,
    input  wire [31:0] err_ts,


    output wire [3:0]  evt_type,
    output wire [15:0] evt_value,
    output wire        evt_valid,
    output wire        evt_full,
    input  wire        evt_ready,
    output wire [31:0] evt_ts,


    output reg  [15:0] drop_cnt
);

    localparam integer EVT_W        = 44;
    localparam integer EVT_DEPTH    = 8;
    localparam integer EVT_AFULL_TH = 6;
    localparam integer EVT_AEMPTY_TH= 1;

    wire [EVT_W-1:0] evt_head;
    wire             evt_empty;
    wire             evt_almost_full;


    wire [43:0] push_data = {err_ts, err_code, err_src};


    wire evt_wr = err_push & ~evt_full;

    sync_fifo #(
        .W               (EVT_W),
        .DEPTH           (EVT_DEPTH),
        .ALMOST_FULL_TH  (EVT_AFULL_TH),
        .ALMOST_EMPTY_TH (EVT_AEMPTY_TH)
    ) u_evt_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (evt_wr),
        .din          (push_data),
        .full         (evt_full),
        .almost_full  (evt_almost_full),
        .rd_en        (evt_valid && (evt_ready === 1'b1)),
        .dout         (evt_head),
        .empty        (evt_empty),
        .almost_empty (),
        .data_count   ()
    );


    assign evt_valid = ~evt_empty;
    assign evt_type  = evt_head[3:0];
    assign evt_value = {8'h00, evt_head[11:4]};
    assign evt_ts    = evt_head[43:12];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drop_cnt <= 16'd0;
        end else if (err_push && evt_full) begin
            if (drop_cnt != 16'hffff) drop_cnt <= drop_cnt + 16'd1;
        end
    end

endmodule
