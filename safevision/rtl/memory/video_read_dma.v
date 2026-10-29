


`include "safevision_defs.vh"

module video_read_dma #(
    parameter integer BURST_WORDS = 16,
    parameter integer PIX_DEPTH   = 512,
    parameter integer LOW_WATER   = 64,
    parameter integer STREAMING   = 0
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire        start,
    input  wire [31:0] frame_base,
    input  wire [15:0] pix_fifo_level,


    output reg         rd_req,
    output reg  [31:0] rd_addr,
    output reg  [15:0] rd_len,
    input  wire        rd_ack,
    input  wire        rd_busy,
    input  wire [31:0] rd_data,
    input  wire        rd_data_valid,


    output reg  [15:0] fifo_wr_data,
    output reg         fifo_wr_en,


    output reg  [31:0] rd_bytes_cnt,
    output reg         active,
    output reg         done
);


    localparam integer FRAME_W     = `SV_FRAME_WIDTH;
    localparam integer FRAME_H     = `SV_FRAME_HEIGHT;
    localparam [31:0]  FRAME_BYTES = FRAME_W * FRAME_H * `SV_RGB565_BYTES_PER_PX;
    function integer index_width;
        input integer n;
        integer v;
        begin
            index_width=1;
            for(v=n-1;v>1;v=v>>1) index_width=index_width+1;
        end
    endfunction
    localparam integer INDEX_W=index_width(BURST_WORDS);


    localparam integer FRAME_WORDS=FRAME_BYTES/4;
    localparam integer LAST_WORDS=(FRAME_WORDS%BURST_WORDS)==0 ?
                                  BURST_WORDS : FRAME_WORDS%BURST_WORDS;
    localparam [31:0] LAST_OFFSET=(FRAME_WORDS-LAST_WORDS)*4;
    localparam [15:0] FULL_SPACE_LIMIT=PIX_DEPTH-BURST_WORDS*2;
    localparam [15:0] LAST_SPACE_LIMIT=PIX_DEPTH-LAST_WORDS*2;
    wire last_burst=(rd_bytes_cnt==LAST_OFFSET);
    wire [15:0] next_burst_words=last_burst ? LAST_WORDS : BURST_WORDS;
    wire fifo_has_space=(pix_fifo_level <=
                         (last_burst ? LAST_SPACE_LIMIT : FULL_SPACE_LIMIT));
    reg [15:0] burst_words;
    // synthesis translate_off
    initial if(BURST_WORDS<1 || BURST_WORDS>65535 || PIX_DEPTH<1 ||
        PIX_DEPTH>65535 || BURST_WORDS*2>PIX_DEPTH || LOW_WATER<1 || LOW_WATER>PIX_DEPTH)
        $fatal(1,"video_read_dma invalid burst/FIFO parameters");
    // synthesis translate_on

    localparam [2:0] V_IDLE    = 3'd0,
                     V_CHECK   = 3'd1,
                     V_WAITACK = 3'd2,
                     V_COLLECT = 3'd3,
                     V_DRAIN   = 3'd4,
                     V_SETTLE  = 3'd5;

    reg  [2:0]  state;
    reg  [31:0] base;
    reg  [31:0] rd_buf [0:BURST_WORDS-1];
    reg  [INDEX_W-1:0] collect_cnt;
    reg  [INDEX_W-1:0] drain_word;
    reg         drain_half;
    reg [INDEX_W:0] collected,drained;


    wire capture_at_ack = (state == V_WAITACK) && rd_ack;
    wire capture_word = rst_n && rd_data_valid &&
                        (capture_at_ack || (state == V_COLLECT));
    wire [INDEX_W-1:0] capture_index = capture_at_ack ?
                                      {INDEX_W{1'b0}} : collect_cnt;
    always @(posedge clk) begin
        if (capture_word) rd_buf[capture_index] <= rd_data;
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= V_IDLE;
            burst_words  <= 0;
            base         <= 32'd0;
            collect_cnt  <= 0;
            drain_word   <= 0;
            drain_half   <= 1'b0;
            collected<=0;drained<=0;
            rd_req       <= 1'b0;
            rd_addr      <= 32'd0;
            rd_len       <= 16'd0;
            fifo_wr_data <= 16'd0;
            fifo_wr_en   <= 1'b0;
            rd_bytes_cnt <= 32'd0;
            active       <= 1'b0;
            done         <= 1'b0;
        end else begin

            done       <= 1'b0;
            fifo_wr_en <= 1'b0;

            case (state)

            V_IDLE: begin
                if (start) begin
                    base         <= frame_base;
                    rd_bytes_cnt <= 32'd0;
                    active       <= 1'b1;
                    rd_req       <= 1'b0;
                    state        <= V_CHECK;
                end
            end

            V_CHECK: begin
                if (rd_bytes_cnt >= FRAME_BYTES) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                    state  <= V_IDLE;
                end else if ((pix_fifo_level < LOW_WATER) &&
                             fifo_has_space) begin
                    rd_addr <= base + rd_bytes_cnt;
                    rd_len  <= next_burst_words;
                    burst_words <= next_burst_words;
                    rd_req  <= 1'b1;
                    state   <= V_WAITACK;
                end
            end

            V_WAITACK: begin
                if (rd_ack) begin
                    rd_req      <= 1'b0;
                    collect_cnt <= 0;
                    collected<=rd_data_valid?1:0;drained<=0;drain_word<=0;drain_half<=0;
                    state       <= V_COLLECT;

                    if(rd_data_valid) begin
                        if(burst_words==1 && !STREAMING) begin
                            rd_bytes_cnt <= rd_bytes_cnt+32'd4;
                            drain_word <= 0;
                            drain_half <= 0;
                            state <= V_DRAIN;
                        end else collect_cnt <= 1;
                    end
                end
            end

            V_COLLECT: begin
                if (rd_data_valid) begin
                    if(STREAMING)begin
                        collected<=collected+1'b1;
                        collect_cnt<=collect_cnt+1'b1;
                    end else if (collect_cnt == (burst_words-1)) begin
                        rd_bytes_cnt <= rd_bytes_cnt + {14'd0,burst_words,2'b00};
                        drain_word   <= 0;
                        drain_half   <= 1'b0;
                        state        <= V_DRAIN;
                    end else begin
                        collect_cnt <= collect_cnt + 1'b1;
                    end
                end
                if(STREAMING && drained<collected)begin


                    fifo_wr_en<=1;
                    fifo_wr_data<=drain_half?rd_buf[drain_word][31:16]:rd_buf[drain_word][15:0];
                    if(drain_half)begin
                        drain_half<=0;drained<=drained+1'b1;
                        if(drained==burst_words-1'b1)begin
                            rd_bytes_cnt<=rd_bytes_cnt+{14'd0,burst_words,2'b00};state<=V_SETTLE;
                        end else drain_word<=drain_word+1'b1;
                    end else drain_half<=1;
                end
            end

            V_DRAIN: begin
                fifo_wr_en   <= 1'b1;
                fifo_wr_data <= drain_half ? rd_buf[drain_word][31:16]
                                           : rd_buf[drain_word][15:0];
                if (drain_half) begin
                    if (drain_word == (burst_words-1)) begin
                        state <= V_SETTLE;
                    end else begin
                        drain_word <= drain_word + 1'b1;
                        drain_half <= 1'b0;
                    end
                end else begin
                    drain_half <= 1'b1;
                end
            end
            V_SETTLE: state <= V_CHECK;
            default: state <= V_IDLE;
            endcase
        end
    end

endmodule
