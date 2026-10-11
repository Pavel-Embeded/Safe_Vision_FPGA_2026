`include "pixel_format_defs.vh"
// Signatures originate at accepted producer words, BEFORE SDRAM storage.
// Two synchronous readers permit playback during inactive-slot verification.
// No RAM reset: slot validity gates stale contents after every common reset.
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
    output reg [31:0] last_read_word,    // 诊断 v4：校验过程里**最后一次**读回的第 0 个字
    output reg [11:0] fail_cnt,          // 诊断 v4：2400 块里 CRC 不符的块数
    output reg [31:0] source_words,output reg [15:0] checked_blocks
);
    `include "crc32_word.vh"
    localparam integer BLOCKS=WORDS/BLOCK_WORDS;
    localparam [2:0] IDLE=0,REQUEST=1,COLLECT=2,CHECK=3,RETIRE=4,FINISHED=5;
`ifdef SAFEVISION_DIAG_WORDPROBE
    localparam DIAG_KEEP_VERIFYING=1'b1;   // v4：首块失败后**继续**校验（统计 fail_cnt）
`else
    localparam DIAG_KEEP_VERIFYING=1'b0;   // 默认位流：行为与原来逐位一致
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
    // ★ 诊断 v4（2026-10-11）。在 v3（反向校验 + 原始读回字）基础上再补两个判据，
    //   目标是回答"读通路是整体坏还是只有开头坏"：
    //
    //   ③ 首块失败后**不再停下**，把 2400 块全部校验完，用 fail_cnt 统计坏块数。
    //      报文 `B` 低 12 位 = fail_cnt：
    //        · 2400 ⇒ **所有块读回都错** ⇒ 读通路/存储器整体失效（不是局部问题）
    //        · 1    ⇒ **只有最先校验的那一块错** ⇒ 写→读切换处的一次性问题
    //        · 其它 ⇒ 局部/区间性损坏
    //      （v3 的 B 是"已通过块数"，v4 换成"坏块数"；二者互补：2400-fail_cnt=通过数。）
    //
    //   ④ `last_read_word` = **整个校验过程最后一次读回的第 0 个字**。
    //      反向校验下最后一次读的是第 0 块（槽基址）⇒ 若它仍是 FFFFFFFF，
    //      说明读到最后一刻都还是全 1；若它是真实的图像数据，则说明读通路本身是好的、
    //      只是"刚开始读的那一段"坏。
`endif
    // ★ 声明必须放在 `ifdef` **外面**：复位分支（无条件）会引用它们。
    //   默认位流里它们只被复位赋值、从不被读 ⇒ 综合时会被优化掉，不占资源。
    reg [31:0] blk_w0,blk_w1;
    wire addr_slot=write_addr>=`SV_IMG1_BASE;
    wire [31:0] word_offset=write_addr-(addr_slot?`SV_IMG1_BASE:`SV_IMG0_BASE);
    wire [12:0] write_index=(addr_slot?BLOCKS:0)+(word_offset>>8);
    wire query_slot=lookup_addr>=`SV_IMG1_BASE;
    wire [31:0] query_offset=lookup_addr-(query_slot?`SV_IMG1_BASE:`SV_IMG0_BASE);
    wire [12:0] query_index=(query_slot?BLOCKS:0)+(query_offset>>8);
    // frame_begin precedes the BMP header result. Match the bridge's contract:
    // latch orientation on the first accepted word, when the header is valid.
    // Later words use only this latched direction and the sequential address.
    wire [31:0] source_expected=(source_words==0)?
        base+(top_down?0:(WORDS-ROW_WORDS)*4):expected_addr;
    wire source_beat=building&&accepted&&!fault&&write_addr==source_expected;
    wire signature_write=source_beat&&in_block==BLOCK_WORDS-1;
    // Port B writes while building and reads while verifying. These phases
    // never overlap; a true dual-port RAM also serves playback on port A.
`ifdef SAFEVISION_DIAG_WORDPROBE
    // ★ v3 反向校验：迭代计数 verify_index 与**块号**解耦。
    //   正序时二者相等，反序时必须显式映射 —— 签名索引、读地址都必须用块号。
    //   （踩过：只改读地址不改签名索引 ⇒ 每块都拿错签名，第 1 块就报错。）
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
            // v3 不需要写入侧影子：失败块的读回字在 capture 处直接抓（见下）。
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
                            // ★ v4：全部 2400 块校验完才收尾；fail_cnt>0 就不发布该槽。
                            verify_done<=1;state<=FINISHED;
                            if(fail_cnt==0)begin approved[slot_latched]<=1;verify_pass<=1;end
                            else verify_pass<=0;
`else
                            approved[slot_latched]<=1;verify_done<=1;verify_pass<=1;state<=FINISHED;
`endif
                        end else begin
`ifdef SAFEVISION_DIAG_WORDPROBE
                            // ★ v3：反向校验（末块 → 第 0 块）。地址用 verify_block，
                            //   与签名索引严格同源（见 second_index 处的注释）。
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
                        // ★ v4：只锁存**第一处**失败的 BAD/EXP/GOT，但**不停下**，
                        //   继续把 2400 块校验完，用 fail_cnt 统计坏块总数。
                        if(!fault)begin
                            fault<=1;bad_addr<=rd_addr;
                            bad_expected<=blk_w0;bad_actual<=blk_w1;   // 该块原始读回字 0/1
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
                    // ★ v4：每块都会覆盖这两个值。
                    //   blk_w0/blk_w1 = 当前块的第 0/1 个读回字（CHECK 失败时即该失败块的值）；
                    //   last_read_word = 最后一次读回的第 0 个字（校验跑完时=最后一块的值）。
                    if(response_count==0)begin blk_w0<=rd_data;last_read_word<=rd_data;end
                    if(response_count==1)blk_w1<=rd_data;
`endif
                    if(response_count==BLOCK_WORDS-1)begin
                        block_crc<=~crc32_word(verify_crc,rd_data);state<=CHECK;
                    end
                end
                // Failure overrides all other state transitions on this edge.
                if(timed_out)begin
                    fault<=1;verify_done<=1;verify_pass<=0;rd_req<=0;state<=FINISHED;
                    bad_addr<=rd_addr;bad_expected<=verify_expected;bad_actual<=block_crc;
                end
            end else rd_req<=0;
        end
    end
    // synthesis translate_off
    initial if(BLOCK_WORDS!=64||WORDS%BLOCK_WORDS||ROW_WORDS%BLOCK_WORDS||BLOCKS>2400)
        $fatal(1,"unsupported signature geometry");
    // synthesis translate_on
endmodule
