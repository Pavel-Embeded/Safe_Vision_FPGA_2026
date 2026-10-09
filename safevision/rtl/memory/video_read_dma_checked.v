// Board integrity DMA. Two landing banks overlap fetch and pixel drain.
// A bank becomes visible to the pixel FIFO only after its complete CRC matches
// the signature of the accepted producer words. No unverified word is emitted.
// The legacy DMA remains available for interfaces without a signature store.
module video_read_dma_checked #(
    parameter integer BURST_WORDS=64,PIX_DEPTH=4094,LOW_WATER=3800,
    parameter integer FRAME_WORDS=153600,
    parameter [31:0] WAIT_TIMEOUT=32'd4000000
)(
    input wire clk,rst_n,start,input wire [31:0] frame_base,
    input wire [15:0] pix_fifo_level,
    output reg rd_req,output reg [31:0] rd_addr,output wire [15:0] rd_len,
    input wire rd_ack,rd_busy,input wire [31:0] rd_data,input wire rd_data_valid,
    input wire [31:0] expected_crc,input wire expected_valid,
    output reg [15:0] fifo_wr_data,output reg fifo_wr_en,
    output reg [31:0] rd_bytes_cnt,output reg active,done,fault,
    output reg [31:0] bad_addr,bad_expected,bad_actual
);
    `include "crc32_word.vh"
    function integer width;
        input integer n;integer v;
        begin width=1;for(v=n-1;v>1;v=v>>1)width=width+1;end
    endfunction
    localparam integer BW=width(BURST_WORDS);
    localparam [2:0] IDLE=0,REQUEST=1,COLLECT=2,CHECK=3,RETIRE=4;
    localparam integer RESERVE=4*BURST_WORDS+8;
    localparam [15:0] SPACE_LIMIT=PIX_DEPTH-RESERVE;
    reg [2:0] read_state;
    reg fill_bank,next_fill,next_drain,drain_bank,draining,drain_half;
    reg [1:0] bank_ready;
    reg [BW:0] fill_count;
    reg [BW-1:0] drain_index;
    reg [31:0] landing[0:2*BURST_WORDS-1];
    reg [31:0] base,issued_words,drained_words,crc_state,burst_crc,wait_count;
    reg [1:0] settle;
    wire capture=rd_data_valid&&((read_state==REQUEST&&rd_ack)||read_state==COLLECT);
    wire [BW:0] fill_address={fill_bank,fill_count[BW-1:0]};
    wire [BW:0] drain_address={drain_bank,drain_index};
    assign rd_len=BURST_WORDS;
    always @(posedge clk)
        if(rst_n&&active&&!fault&&capture&&fill_count<BURST_WORDS)
            landing[fill_address]<=rd_data;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            rd_req<=0;rd_addr<=0;fifo_wr_data<=0;fifo_wr_en<=0;
            rd_bytes_cnt<=0;active<=0;done<=0;fault<=0;
            bad_addr<=0;bad_expected<=0;bad_actual<=0;
            read_state<=IDLE;fill_bank<=0;next_fill<=0;next_drain<=0;
            drain_bank<=0;draining<=0;drain_half<=0;bank_ready<=0;
            fill_count<=0;drain_index<=0;base<=0;issued_words<=0;drained_words<=0;
            crc_state<=32'hffffffff;burst_crc<=0;wait_count<=0;settle<=0;
        end else begin
            fifo_wr_en<=0;done<=0;
            if(start&&!active&&!fault)begin
                base<=frame_base;issued_words<=0;drained_words<=0;rd_bytes_cnt<=0;
                bank_ready<=0;next_fill<=0;next_drain<=0;draining<=0;
                read_state<=IDLE;rd_req<=0;active<=1;settle<=0;wait_count<=0;
            end else if(active&&!fault)begin
                if(read_state==REQUEST||read_state==COLLECT||read_state==RETIRE)begin
                    if(rd_ack||capture)wait_count<=0;
                    else if(wait_count>=WAIT_TIMEOUT)begin
                        fault<=1;active<=0;rd_req<=0;draining<=0;bank_ready<=0;
                        bad_addr<=rd_addr;bad_expected<=expected_crc;bad_actual<=burst_crc;
                    end else wait_count<=wait_count+1'b1;
                end else wait_count<=0;
                case(read_state)
                    IDLE:if(issued_words<FRAME_WORDS&&!rd_busy&&!bank_ready[next_fill]&&
                          !(draining&&drain_bank==next_fill)&&pix_fifo_level<=SPACE_LIMIT&&
                          pix_fifo_level<LOW_WATER)begin
                        fill_bank<=next_fill;fill_count<=0;crc_state<=32'hffffffff;
                        rd_addr<=base+(issued_words<<2);rd_req<=1;read_state<=REQUEST;
                    end
                    REQUEST:if(rd_ack)begin rd_req<=0;read_state<=COLLECT;end
                    COLLECT:;
                    CHECK:begin
                        if(!expected_valid||burst_crc!=expected_crc)begin
                            fault<=1;active<=0;rd_req<=0;draining<=0;bank_ready<=0;fifo_wr_en<=0;
                            bad_addr<=rd_addr;bad_expected<=expected_crc;bad_actual<=burst_crc;
                        end else begin bank_ready[fill_bank]<=1;read_state<=RETIRE;end
                    end
                    RETIRE:if(!rd_busy)begin
                        issued_words<=issued_words+BURST_WORDS;next_fill<=~next_fill;read_state<=IDLE;
                    end
                    default:read_state<=IDLE;
                endcase
                if(capture)begin
                    crc_state<=crc32_word(crc_state,rd_data);
                    fill_count<=fill_count+1'b1;
                    if(fill_count==BURST_WORDS-1)begin
                        burst_crc<=~crc32_word(crc_state,rd_data);read_state<=CHECK;
                    end
                end
                if(!draining&&bank_ready[next_drain])begin
                    draining<=1;drain_bank<=next_drain;drain_index<=0;drain_half<=0;
                end else if(draining)begin
                    fifo_wr_en<=1;
                    fifo_wr_data<=drain_half ? landing[drain_address][31:16] : landing[drain_address][15:0];
                    if(!drain_half)drain_half<=1;
                    else begin
                        drain_half<=0;
                        if(drain_index==BURST_WORDS-1)begin
                            draining<=0;bank_ready[drain_bank]<=0;next_drain<=~next_drain;
                            drained_words<=drained_words+BURST_WORDS;
                            rd_bytes_cnt<=rd_bytes_cnt+BURST_WORDS*4;
                            if(drained_words==FRAME_WORDS-BURST_WORDS)settle<=2;
                        end else drain_index<=drain_index+1'b1;
                    end
                end
                // Last registered pixel reaches the FIFO one edge later.
                if(settle!=0)begin
                    settle<=settle-1'b1;
                    if(settle==1)begin done<=1;active<=0;end
                end
                if((read_state==CHECK&&(!expected_valid||burst_crc!=expected_crc))||
                   ((read_state==REQUEST||read_state==COLLECT||read_state==RETIRE)&&
                    !rd_ack&&!capture&&wait_count>=WAIT_TIMEOUT))begin
                    fault<=1;active<=0;rd_req<=0;draining<=0;bank_ready<=0;fifo_wr_en<=0;done<=0;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(BURST_WORDS<2||(BURST_WORDS&(BURST_WORDS-1))!=0||
               FRAME_WORDS%BURST_WORDS!=0||PIX_DEPTH<=RESERVE||LOW_WATER<1)
        $fatal(1,"checked DMA requires power-of-two blocks and a complete frame");
    // synthesis translate_on
endmodule
