


`include "safevision_defs.vh"

module memory_arbiter #(
    parameter integer MAX_BURSTS   = 4,
    parameter integer STARVE_LIMIT = 64,


    parameter integer COMPACT_CONSEC_COUNTER = 0,


    parameter [15:0] HIGH_WATER = 16'd48,
    parameter [15:0] CRITICAL_WATER = 16'd0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] video_fifo_level,


    input  wire        rd_req,
    input  wire [31:0] rd_addr,
    input  wire [15:0] rd_len,
    output reg         rd_ack,
    output wire        rd_busy,
    output wire [31:0] rd_data,
    output wire        rd_data_valid,


    input  wire        wr_req,
    input  wire [31:0] wr_addr,
    input  wire [31:0] wr_data,
    input  wire [15:0] wr_len,
    output reg         wr_ack,
    output wire        wr_busy,


    input  wire        sd_req,
    input  wire        sd_wr,
    input  wire [31:0] sd_addr,
    input  wire [31:0] sd_wdata,
    input  wire [15:0] sd_len,
    output reg         sd_ack,
    output wire        sd_busy,
    output wire [31:0] sd_rdata,
    output wire        sd_rdata_valid,


    output reg         mem_req,
    output reg         mem_wr,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_wstrb,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,
    input  wire        mem_rdata_valid,


    output reg  [15:0] wr_starve_cnt,
    output reg  [15:0] rd_starve_cnt
);


    localparam [1:0]  CH_NONE = 2'd0,
                      CH_RD   = 2'd1,
                      CH_WR   = 2'd2,
                      CH_SD   = 2'd3;


    localparam [15:0] LOW_WM  = 16'd16;
    localparam [15:0] HIGH_WM = HIGH_WATER;

    localparam [15:0] MAX_BURSTS_C   = MAX_BURSTS;
    localparam [15:0] STARVE_LIMIT_C = STARVE_LIMIT;


    reg  [1:0]  cur_ch;
    reg         busy;
    reg  [15:0] word_left;
    reg         transfer_active;
    reg         cur_wr;
    reg  [15:0] responses_left;
    reg  [31:0] cur_addr;
    reg  [1:0]  last_ch;
    function integer consecutive_width;
        input integer n;
        integer v;
        begin
            consecutive_width=1;
            for(v=n;v>1;v=v>>1)consecutive_width=consecutive_width+1;
        end
    endfunction
    localparam integer CONSEC_WIDTH=COMPACT_CONSEC_COUNTER?
        consecutive_width(MAX_BURSTS):16;
    reg [CONSEC_WIDTH-1:0] consec_cnt;

    reg  [15:0] rd_wait_cnt;
    reg  [15:0] wr_wait_cnt;
    reg         rd_starve_event,wr_starve_event;
    reg         grant_event;
    reg  [1:0]  grant_ch;
    reg  [15:0] sd_wait_cnt;


    wire rd_urg = (rd_wait_cnt >= STARVE_LIMIT_C);
    wire wr_urg = (wr_wait_cnt >= STARVE_LIMIT_C);
    wire sd_urg = (sd_wait_cnt >= STARVE_LIMIT_C);


    wire rd_mask = (last_ch == CH_RD) && (consec_cnt >= MAX_BURSTS_C) &&
                   (wr_req | sd_req) && !rd_urg;
    wire wr_mask = (last_ch == CH_WR) && (consec_cnt >= MAX_BURSTS_C) &&
                   (rd_req | sd_req) && !wr_urg;
    wire sd_mask = (last_ch == CH_SD) && (consec_cnt >= MAX_BURSTS_C) &&
                   (rd_req | wr_req) && !sd_urg;

    wire video_critical = video_fifo_level < CRITICAL_WATER;
    wire rd_e = rd_req & (~rd_mask | video_critical);
    wire wr_e = wr_req & ~wr_mask;
    wire sd_e = sd_req & ~sd_mask;


    wire vid_full = (video_fifo_level > HIGH_WM);


    reg [1:0] winner;
    always @(*) begin
        winner = CH_NONE;
        if (busy) begin
            winner = CH_NONE;
        end else if (video_critical) begin


            winner = rd_e ? CH_RD : CH_NONE;
        end else if (rd_urg && rd_e) begin
            winner = CH_RD;
        end else if (wr_urg && wr_e) begin
            winner = CH_WR;
        end else if (sd_urg && sd_e) begin
            winner = CH_SD;
        end else if (vid_full) begin
            winner = wr_e ? CH_WR : (sd_e ? CH_SD : (rd_e ? CH_RD : CH_NONE));
        end else begin
            winner = rd_e ? CH_RD : (wr_e ? CH_WR : (sd_e ? CH_SD : CH_NONE));
        end
    end


    always @* begin
        mem_req   = busy && transfer_active && (word_left != 0);
        mem_wr    = cur_wr;
        mem_addr  = cur_addr;
        mem_wdata = (cur_ch == CH_WR) ? wr_data : sd_wdata;
        mem_wstrb = cur_wr ? 4'hF : 4'h0;
    end

    wire mem_fire = mem_req && mem_ready;
    wire response_fire = busy && !cur_wr && (responses_left != 0) && mem_rdata_valid;
    wire commands_done = (word_left == 0) || (mem_fire && word_left == 1);
    wire responses_done = cur_wr || (responses_left == 0) ||
                          (response_fire && responses_left == 1);

    assign rd_data       = mem_rdata;
    assign rd_data_valid = response_fire && (cur_ch == CH_RD);
    assign sd_rdata      = mem_rdata;
    assign sd_rdata_valid= response_fire && (cur_ch == CH_SD);
    assign rd_busy = busy && (cur_ch == CH_RD);
    assign wr_busy = busy && (cur_ch == CH_WR);
    assign sd_busy = busy && (cur_ch == CH_SD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_ch <= CH_NONE;
            busy <= 1'b0;
            transfer_active <= 1'b0;
            cur_wr <= 1'b0;
            word_left <= 0;
            responses_left <= 0;
            cur_addr <= 0;
            last_ch <= CH_NONE;
            consec_cnt <= 0;
            rd_wait_cnt <= 0;
            wr_wait_cnt <= 0;
            sd_wait_cnt <= 0;
            rd_ack <= 0;
            wr_ack <= 0;
            sd_ack <= 0;
            wr_starve_cnt <= 0;
            rd_starve_cnt <= 0;
            wr_starve_event <= 0;
            rd_starve_event <= 0;
            grant_event     <= 1'b0;
            grant_ch        <= CH_NONE;
        end else begin
            rd_ack <= 0;
            wr_ack <= 0;
            sd_ack <= 0;


            rd_starve_event <= !busy && rd_urg && winner != CH_RD;
            wr_starve_event <= !busy && wr_urg && winner != CH_WR;
            if(rd_starve_event && rd_starve_cnt != 16'hFFFF)
                rd_starve_cnt <= rd_starve_cnt + 1'b1;
            if(wr_starve_event && wr_starve_cnt != 16'hFFFF)
                wr_starve_cnt <= wr_starve_cnt + 1'b1;


            grant_event <= !busy && (winner != CH_NONE);
            grant_ch    <= winner;
            if (grant_event) begin
                if (last_ch == grant_ch) begin
                    if (consec_cnt != {CONSEC_WIDTH{1'b1}}) consec_cnt <= consec_cnt + 1'b1;
                end else begin
                    last_ch <= grant_ch;
                    consec_cnt <= 1'b1;
                end
            end
            if (!busy) begin
                if (winner != CH_NONE) begin
                    cur_ch <= winner;
                    busy <= 1'b1;
                    transfer_active <= 1'b0;
                    cur_wr <= (winner == CH_WR) || ((winner == CH_SD) && sd_wr);
                    cur_addr <= (winner == CH_RD) ? rd_addr :
                                (winner == CH_WR) ? wr_addr : sd_addr;
                    word_left <= (winner == CH_RD) ? ((rd_len == 0) ? 16'd1 : rd_len) :
                                 (winner == CH_WR) ? ((wr_len == 0) ? 16'd1 : wr_len) :
                                                    ((sd_len == 0) ? 16'd1 : sd_len);
                    if (winner == CH_RD)
                        responses_left <= (rd_len == 0) ? 16'd1 : rd_len;
                    else if (winner == CH_SD && !sd_wr)
                        responses_left <= (sd_len == 0) ? 16'd1 : sd_len;
                    else responses_left <= 0;
                    case (winner)
                        CH_RD: rd_ack <= 1'b1;
                        CH_WR: wr_ack <= 1'b1;
                        CH_SD: sd_ack <= 1'b1;
                        default: ;
                    endcase


                end
            end else begin

                transfer_active <= 1'b1;
                if (mem_fire) begin
                    cur_addr <= cur_addr + 32'd4;
                    word_left <= word_left - 1'b1;
                end
                if (response_fire) responses_left <= responses_left - 1'b1;
                if (commands_done && responses_done) begin
                    busy <= 1'b0;
                    transfer_active <= 1'b0;
                end
            end


            if (rd_req && !(busy && cur_ch == CH_RD)) begin
                if (rd_wait_cnt != 16'hFFFF) rd_wait_cnt <= rd_wait_cnt + 1'b1;
            end else rd_wait_cnt <= 0;
            if (wr_req && !(busy && cur_ch == CH_WR)) begin
                if (wr_wait_cnt != 16'hFFFF) wr_wait_cnt <= wr_wait_cnt + 1'b1;
            end else wr_wait_cnt <= 0;
            if (sd_req && !(busy && cur_ch == CH_SD)) begin
                if (sd_wait_cnt != 16'hFFFF) sd_wait_cnt <= sd_wait_cnt + 1'b1;
            end else sd_wait_cnt <= 0;
        end
    end
endmodule
