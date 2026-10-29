`include "pixel_format_defs.vh"


module frame_integrity_guard #(
    parameter integer WORDS=153600,ROW_WORDS=320,BLOCK_WORDS=64,
    parameter [31:0] TIMEOUT=32'd40000000
)(
    input wire clk,rst_n,frame_begin,input wire [1:0] frame_slot,
    input wire top_down,accepted,input wire [31:0] write_addr,write_data,
    input wire verify_start,verify_allow,
    output reg verify_done,verify_pass,fault,
    output reg rd_req,output reg [31:0] rd_addr,output wire [15:0] rd_len,
    input wire rd_ack,rd_busy,input wire [31:0] rd_data,input wire rd_valid,
    input wire [31:0] lookup_addr,
    output reg [31:0] lookup_crc,output reg lookup_valid,
    output reg [31:0] bad_addr,bad_expected,bad_actual,
    output reg [31:0] last_read_word,
    output reg [11:0] fail_cnt,
    output reg [31:0] source_words,output reg [15:0] checked_blocks
);
    `include "crc32_word.vh"
    localparam integer BLOCKS=WORDS/BLOCK_WORDS;
    localparam [2:0] IDLE=0,REQUEST=1,COLLECT=2,CHECK=3,RETIRE=4,FINISHED=5;
`ifdef SAFEVISION_DIAG_WORDPROBE
    localparam DIAG_KEEP_VERIFYING=1'b1;
`else
    localparam DIAG_KEEP_VERIFYING=1'b0;
`endif
    reg [31:0] signatures[0:2*BLOCKS-1];
    reg [1:0] approved;
    reg slot_latched,direction,source_complete,building;
    reg [31:0] source_crc,expected_addr,base,verify_crc,block_crc,timer;
    reg [8:0] column;
    reg [5:0] in_block;
    reg [6:0] response_count;
    reg [11:0] verify_index;
    reg [2:0] state;
    reg [31:0] verify_expected;
`ifdef SAFEVISION_DIAG_WORDPROBE


`endif


    reg [31:0] blk_w0,blk_w1;
    wire addr_slot=write_addr>=`SV_IMG1_BASE;
    wire [31:0] word_offset=write_addr-(addr_slot?`SV_IMG1_BASE:`SV_IMG0_BASE);
    wire [12:0] write_index=(addr_slot?BLOCKS:0)+(word_offset>>8);
    wire query_slot=lookup_addr>=`SV_IMG1_BASE;
    wire [31:0] query_offset=lookup_addr-(query_slot?`SV_IMG1_BASE:`SV_IMG0_BASE);
    wire [12:0] query_index=(query_slot?BLOCKS:0)+(query_offset>>8);


    wire [31:0] source_expected=(source_words==0)?
        base+(top_down?0:(WORDS-ROW_WORDS)*4):expected_addr;
    wire source_beat=building&&accepted&&!fault&&write_addr==source_expected;
    wire signature_write=source_beat&&in_block==BLOCK_WORDS-1;


`ifdef SAFEVISION_DIAG_WORDPROBE


    wire [11:0] verify_block=BLOCKS-1-verify_index;
`else
    wire [11:0] verify_block=verify_index;
`endif
    wire [12:0] second_index=signature_write?write_index:((slot_latched?BLOCKS:0)+verify_block);
    wire capture=rd_valid&&((state==REQUEST&&rd_ack)||state==COLLECT);
    wire timed_out=(state!=IDLE&&state!=FINISHED&&timer>=TIMEOUT);
    assign rd_len=BLOCK_WORDS;
    always @(posedge clk)begin
        if(signature_write)signatures[second_index]<=~crc32_word(source_crc,write_data);
        verify_expected<=signatures[second_index];
        lookup_crc<=signatures[query_index];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            approved<=0;lookup_valid<=0;slot_latched<=0;direction<=0;
            source_complete<=0;building<=0;source_crc<=32'hffffffff;
            expected_addr<=0;base<=0;column<=0;in_block<=0;source_words<=0;
            verify_done<=0;verify_pass<=0;fault<=0;rd_req<=0;rd_addr<=0;
            state<=IDLE;verify_index<=0;response_count<=0;verify_crc<=32'hffffffff;
            block_crc<=0;timer<=0;checked_blocks<=0;bad_addr<=0;bad_expected<=0;bad_actual<=0;
            blk_w0<=0;blk_w1<=0;fail_cnt<=0;last_read_word<=0;
        end else begin
            lookup_valid<=approved[query_slot]&&query_offset<WORDS*4&&lookup_addr[7:0]==0;
            if(frame_begin&&!fault)begin
                slot_latched<=frame_slot[0];direction<=top_down;
                base<=frame_slot[0]?`SV_IMG1_BASE:`SV_IMG0_BASE;
                expected_addr<=(frame_slot[0]?`SV_IMG1_BASE:`SV_IMG0_BASE)+
                              (top_down?0:(WORDS-ROW_WORDS)*4);
                approved[frame_slot[0]]<=0;building<=1;source_complete<=0;
                source_words<=0;column<=0;in_block<=0;source_crc<=32'hffffffff;
                verify_done<=0;verify_pass<=0;state<=IDLE;checked_blocks<=0;
`ifdef SAFEVISION_DIAG_WORDPROBE
                fail_cnt<=0;
`endif
                if(frame_slot>1)begin fault<=1;building<=0;bad_addr<=write_addr;end
            end else if(building&&accepted&&!fault)begin
                if(write_addr!=source_expected||addr_slot!=slot_latched)begin
                    fault<=1;building<=0;bad_addr<=write_addr;bad_expected<=source_expected;bad_actual<=write_addr;
                end else begin
                    if(source_words==0)direction<=top_down;
                    source_words<=source_words+1'b1;
                    if(in_block==BLOCK_WORDS-1)begin in_block<=0;source_crc<=32'hffffffff;end
                    else begin in_block<=in_block+1'b1;source_crc<=crc32_word(source_crc,write_data);end
                    if(column==ROW_WORDS-1)begin
                        column<=0;expected_addr<=direction?expected_addr+4:expected_addr-ROW_WORDS*8+4;
                    end else begin column<=column+1'b1;expected_addr<=source_expected+4;end
                    if(source_words==WORDS-1)begin source_complete<=1;building<=0;end
                end
            end
`ifdef SAFEVISION_DIAG_WORDPROBE

`endif
            if(!fault||DIAG_KEEP_VERIFYING)begin
                if(state!=IDLE&&state!=FINISHED)begin
                    if(rd_ack||capture)timer<=0;else timer<=timer+1'b1;
                end else timer<=0;
                case(state)
                    IDLE:if(verify_start)begin
                        if(!source_complete)begin fault<=1;verify_done<=1;verify_pass<=0;bad_expected<=WORDS;bad_actual<=source_words;end
                        else begin verify_index<=0;state<=RETIRE;end
                    end
                    RETIRE:if(!rd_busy&&verify_allow)begin
                        if(verify_index==BLOCKS)begin
`ifdef SAFEVISION_DIAG_WORDPROBE

                            verify_done<=1;state<=FINISHED;
                            if(fail_cnt==0)begin approved[slot_latched]<=1;verify_pass<=1;end
                            else verify_pass<=0;
`else
                            approved[slot_latched]<=1;verify_done<=1;verify_pass<=1;state<=FINISHED;
`endif
                        end else begin
`ifdef SAFEVISION_DIAG_WORDPROBE


                            rd_addr<=base+(verify_block*BLOCK_WORDS*4);
`else
                            rd_addr<=base+verify_index*BLOCK_WORDS*4;
`endif
                            rd_req<=1;
                            response_count<=0;verify_crc<=32'hffffffff;state<=REQUEST;
                        end
                    end
                    REQUEST:if(rd_ack)begin rd_req<=0;state<=COLLECT;end
                    COLLECT:;
                    CHECK:if(block_crc!=verify_expected)begin
`ifdef SAFEVISION_DIAG_WORDPROBE


                        if(!fault)begin
                            fault<=1;bad_addr<=rd_addr;
                            bad_expected<=blk_w0;bad_actual<=blk_w1;
                        end
                        if(fail_cnt!=12'hFFF)fail_cnt<=fail_cnt+1'b1;
                        verify_index<=verify_index+1'b1;state<=RETIRE;
`else
                        fault<=1;verify_done<=1;verify_pass<=0;bad_addr<=rd_addr;
                        bad_expected<=verify_expected;bad_actual<=block_crc;
                        state<=FINISHED;
`endif
                    end else begin
                        checked_blocks<=checked_blocks+1'b1;verify_index<=verify_index+1'b1;state<=RETIRE;
                    end
                    FINISHED:;
                    default:state<=IDLE;
                endcase
                if(capture)begin
                    response_count<=response_count+1'b1;verify_crc<=crc32_word(verify_crc,rd_data);
`ifdef SAFEVISION_DIAG_WORDPROBE


                    if(response_count==0)begin blk_w0<=rd_data;last_read_word<=rd_data;end
                    if(response_count==1)blk_w1<=rd_data;
`endif
                    if(response_count==BLOCK_WORDS-1)begin
                        block_crc<=~crc32_word(verify_crc,rd_data);state<=CHECK;
                    end
                end

                if(timed_out)begin
                    fault<=1;verify_done<=1;verify_pass<=0;rd_req<=0;state<=FINISHED;
                    bad_addr<=rd_addr;bad_expected<=verify_expected;bad_actual<=block_crc;
                end
            end else rd_req<=0;
        end
    end
    // synthesis translate_off
    initial if(BLOCK_WORDS!=64||WORDS%BLOCK_WORDS||ROW_WORDS%BLOCK_WORDS||BLOCKS>2400)
        begin $display("[FAIL] unsupported signature geometry"); $finish; end 
    // synthesis translate_on
endmodule
