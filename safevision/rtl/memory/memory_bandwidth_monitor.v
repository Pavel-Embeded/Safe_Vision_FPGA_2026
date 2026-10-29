


module memory_bandwidth_monitor #(
    parameter integer CLK_MHZ = 125
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire [31:0] wr_bytes,
    input  wire        wr_valid,
    input  wire [31:0] rd_bytes,
    input  wire        rd_valid,


    input  wire [31:0] window_cycles,


    output reg  [31:0] rd_bytes_total,
    output reg  [31:0] wr_bytes_total,
    output reg  [31:0] rd_bw_mbps,
    output reg  [31:0] wr_bw_mbps,
    output reg         window_done
);

    localparam [63:0] CLK_MHZ_W = CLK_MHZ;

    reg [31:0] cyc;
    reg [31:0] win_rd;
    reg [31:0] win_wr;


    wire [31:0] rd_acc_next = win_rd + (rd_valid ? rd_bytes : 32'd0);
    wire [31:0] wr_acc_next = win_wr + (wr_valid ? wr_bytes : 32'd0);


    wire [63:0] rd_bw_calc = (window_cycles == 32'd0) ? 64'd0
                           : ({{32{1'b0}}, rd_acc_next} * CLK_MHZ_W)
                             / {{32{1'b0}}, window_cycles};
    wire [63:0] wr_bw_calc = (window_cycles == 32'd0) ? 64'd0
                           : ({{32{1'b0}}, wr_acc_next} * CLK_MHZ_W)
                             / {{32{1'b0}}, window_cycles};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cyc            <= 32'd0;
            win_rd         <= 32'd0;
            win_wr         <= 32'd0;
            rd_bytes_total <= 32'd0;
            wr_bytes_total <= 32'd0;
            rd_bw_mbps     <= 32'd0;
            wr_bw_mbps     <= 32'd0;
            window_done    <= 1'b0;
        end else begin
            window_done <= 1'b0;

            if (window_cycles == 32'd0) begin

                cyc <= 32'd0;
            end else if (cyc == window_cycles - 32'd1) begin

                cyc            <= 32'd0;
                win_rd         <= 32'd0;
                win_wr         <= 32'd0;
                rd_bytes_total <= rd_bytes_total + rd_acc_next;
                wr_bytes_total <= wr_bytes_total + wr_acc_next;
                rd_bw_mbps     <= rd_bw_calc[31:0];
                wr_bw_mbps     <= wr_bw_calc[31:0];
                window_done    <= 1'b1;
            end else begin
                cyc    <= cyc + 32'd1;
                win_rd <= rd_acc_next;
                win_wr <= wr_acc_next;
            end
        end
    end

endmodule
