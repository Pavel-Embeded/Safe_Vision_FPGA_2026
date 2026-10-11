`include "pixel_format_defs.vh"
// Signatures originate at accepted producer words, BEFORE SDRAM storage.
// Two synchronous readers permit playback during inactive-slot verification.
// No RAM reset: slot validity gates stale contents after every common reset.
module frame_integrity_guard #(
    parameter integer WORDS=153600,ROW_WORDS=320,BLOCK_WORDS=64,SLOTS=2,
    parameter [31:0] TIMEOUT=32'd40000000
)(
    input wire clk,rst_n,frame_begin,frame_abort,input wire [1:0] frame_slot,
    input wire top_down,accepted,input wire [31:0] write_addr,write_data,
    input wire verify_start,verify_allow,
    output reg verify_done,verify_pass,fault,
    output reg rd_req,output reg [31:0] rd_addr,output wire [15:0] rd_len,
    input wire rd_ack,rd_busy,input wire [31:0] rd_data,input wire rd_valid,
    input wire [31:0] lookup_addr,
    output reg [31:0] lookup_crc,output reg lookup_valid,
    output reg [31:0] bad_addr,bad_expected,bad_actual,bad_first_word,
    output reg [31:0] source_words,output reg [15:0] checked_blocks
);
    `include "crc32_word.vh"
    localparam integer BLOCKS=WORDS/BLOCK_WORDS;
    localparam [2:0] IDLE=0,REQUEST=1,COLLECT=2,CHECK=3,RETIRE=4,FINISHED=5;
    function integer width; input integer n; integer v; begin width=1; for(v=n-1;v>1;v=v>>1)width=width+1; end endfunction
    localparam integer INDEX_W=width(SLOTS*BLOCKS),COUNT_W=width(BLOCK_WORDS+1);
    reg [31:0] signatures[0:SLOTS*BLOCKS-1];
    reg [SLOTS-1:0] approved;
    reg [1:0] slot_latched; reg direction,source_complete,building;
    reg [31:0] source_crc,expected_addr,base,verify_crc,block_crc,timer;
    reg [8:0] column;
    reg [COUNT_W-1:0] in_block;
    reg [COUNT_W-1:0] response_count;
    reg [11:0] verify_index;
    reg [2:0] state;
    reg [31:0] verify_expected,first_word;
    wire [1:0] addr_slot=(SLOTS==2)?{1'b0,write_addr>=`SV_IMG1_BASE}:
        ((write_addr>=`SV_IMG3_BASE)?2'd3:(write_addr>=`SV_IMG2_BASE)?2'd2:(write_addr>=`SV_IMG1_BASE)?2'd1:2'd0);
    wire [31:0] word_offset=write_addr-`SV_SLOT_BASE(addr_slot);
    wire [INDEX_W-1:0] write_index=addr_slot*BLOCKS+word_offset/(BLOCK_WORDS*4);
    wire [1:0] query_slot=(SLOTS==2)?{1'b0,lookup_addr>=`SV_IMG1_BASE}:
        ((lookup_addr>=`SV_IMG3_BASE)?2'd3:(lookup_addr>=`SV_IMG2_BASE)?2'd2:(lookup_addr>=`SV_IMG1_BASE)?2'd1:2'd0);
    wire [31:0] query_offset=lookup_addr-`SV_SLOT_BASE(query_slot);
    wire [INDEX_W-1:0] query_index=query_slot*BLOCKS+query_offset/(BLOCK_WORDS*4);
    // frame_begin precedes the BMP header result. Match the bridge's contract:
    // latch orientation on the first accepted word, when the header is valid.
    // Later words use only this latched direction and the sequential address.
    wire [31:0] source_expected=(source_words==0)?
        base+(top_down?0:(WORDS-ROW_WORDS)*4):expected_addr;
    wire source_beat=building&&accepted&&!fault&&write_addr==source_expected;
    wire signature_write=source_beat&&in_block==BLOCK_WORDS-1;
    // Port B writes while building and reads while verifying. These phases
    // never overlap; a true dual-port RAM also serves playback on port A.
    wire [INDEX_W-1:0] second_index=signature_write?write_index:(slot_latched*BLOCKS+verify_index);
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
            block_crc<=0;timer<=0;checked_blocks<=0;bad_addr<=0;bad_expected<=0;bad_actual<=0;first_word<=0;bad_first_word<=0;
        end else begin
            lookup_valid<=approved[query_slot]&&query_offset<WORDS*4&&query_offset%(BLOCK_WORDS*4)==0;
            if(frame_abort&&!fault)begin
                approved[slot_latched]<=0;building<=0;source_complete<=0;verify_done<=0;verify_pass<=0;state<=IDLE;rd_req<=0;
            end else if(frame_begin&&!fault)begin
                slot_latched<=frame_slot;direction<=top_down;
                base<=`SV_SLOT_BASE(frame_slot);
                expected_addr<=(`SV_SLOT_BASE(frame_slot))+
                              (top_down?0:(WORDS-ROW_WORDS)*4);
                approved[frame_slot]<=0;building<=1;source_complete<=0;
                source_words<=0;column<=0;in_block<=0;source_crc<=32'hffffffff;
                verify_done<=0;verify_pass<=0;state<=IDLE;checked_blocks<=0;
                if(frame_slot>=SLOTS)begin fault<=1;building<=0;bad_addr<=write_addr;end
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
            if(!fault&&!frame_abort&&!frame_begin)begin
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
                            approved[slot_latched]<=1;verify_done<=1;verify_pass<=1;state<=FINISHED;
                        end else begin
                            rd_addr<=base+verify_index*BLOCK_WORDS*4;rd_req<=1;
                            response_count<=0;verify_crc<=32'hffffffff;state<=REQUEST;
                        end
                    end
                    REQUEST:if(rd_ack)begin rd_req<=0;state<=COLLECT;end
                    COLLECT:;
                    CHECK:if(block_crc!=verify_expected)begin
                        fault<=1;verify_done<=1;verify_pass<=0;bad_addr<=rd_addr;
                        bad_expected<=verify_expected;bad_actual<=block_crc;bad_first_word<=first_word;state<=FINISHED;
                    end else begin
                        checked_blocks<=checked_blocks+1'b1;verify_index<=verify_index+1'b1;state<=RETIRE;
                    end
                    FINISHED:;
                    default:state<=IDLE;
                endcase
                if(capture)begin
                    if(response_count==0)first_word<=rd_data;
                    response_count<=response_count+1'b1;verify_crc<=crc32_word(verify_crc,rd_data);
                    if(response_count==BLOCK_WORDS-1)begin
                        block_crc<=~crc32_word(verify_crc,rd_data);state<=CHECK;
                    end
                end
                // Failure overrides all other state transitions on this edge.
                if(timed_out)begin
                    fault<=1;verify_done<=1;verify_pass<=0;rd_req<=0;state<=FINISHED;
                    bad_addr<=rd_addr;bad_expected<=verify_expected;bad_actual<=block_crc;bad_first_word<=first_word;
                end
            end else rd_req<=0;
        end
    end
    // synthesis translate_off
    initial if(BLOCK_WORDS<2||WORDS%BLOCK_WORDS||ROW_WORDS%BLOCK_WORDS||BLOCKS>2400||SLOTS<1||SLOTS>4)
        $fatal(1,"unsupported signature geometry");
    // synthesis translate_on
endmodule
