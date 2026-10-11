// 字探针 v4 的行为验证（scratch，不属于正式套件）。
//
// v4 语义（对照 `SAFEVISION_DIAG_WORDPROBE`）：
//   ① 反向校验：末块（BLOCKS-1）→ 第 0 块。
//   ② **首块失败后不停下**，把 2400 块全部校验完；`fail_cnt` = 坏块总数，
//      `checked_blocks` = 通过块数。二者互补（fail_cnt + checked_blocks == BLOCKS）。
//   ③ `bad_addr` = **第一处**失败块基址；`bad_expected/bad_actual` = 该块原始读回字 0/1。
//   ④ `last_read_word` = 整个校验过程**最后一次**读回的第 0 个字
//      （反向校验 ⇒ 最后读的是第 0 块 ⇒ 应等于槽基址 word 0）。
//
// 三个用例：
//   A. 破坏第 0 块 word 5（不影响 word 0）⇒ fail_cnt=1、checked_blocks=2399、
//      bad_addr=SLOT1、last_read_word=pixdata(SLOT1)。
//   B. 破坏末块 word 0 ⇒ fail_cnt=1、bad_addr=LASTB、EXP=被破坏后的字。
//   C. 破坏 3 块（末块 / 中间块 / 第 0 块）⇒ fail_cnt=3、bad_addr=LASTB（反向首块）。
`timescale 1ns/1ps
module tb_wordprobe_check;
    localparam integer WORDS=153600, ROW_WORDS=320, BLOCK_WORDS=64;
    localparam integer BLOCKS=WORDS/BLOCK_WORDS;               // 2400
    localparam [31:0] SLOT1=32'h000A_0000;
    localparam [31:0] LASTB=SLOT1+(BLOCKS-1)*BLOCK_WORDS*4;     // 末块基址 0x00135F00

    reg clk=0; always #12.5 clk=~clk;
    reg rst_n=0, frame_begin=0, accepted=0, verify_start=0, verify_allow=1;
    reg [1:0] frame_slot=0; reg top_down=0;
    reg [31:0] write_addr=0, write_data=0;
    wire verify_done,verify_pass,fault,rd_req; wire [31:0] rd_addr;
    wire [15:0] rd_len;
    reg rd_ack=0,rd_busy=0,rd_valid=0; reg [31:0] rd_data=0;
    wire [31:0] bad_addr,bad_expected,bad_actual,source_words,last_read_word;
    wire [15:0] checked_blocks; wire [11:0] fail_cnt;

    frame_integrity_guard #(.WORDS(WORDS),.ROW_WORDS(ROW_WORDS),
        .BLOCK_WORDS(BLOCK_WORDS),.TIMEOUT(32'd4000000)) dut (
        .clk(clk),.rst_n(rst_n),.frame_begin(frame_begin),.frame_slot(frame_slot),
        .top_down(top_down),.accepted(accepted),.write_addr(write_addr),.write_data(write_data),
        .verify_start(verify_start),.verify_allow(verify_allow),
        .verify_done(verify_done),.verify_pass(verify_pass),.fault(fault),
        .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),
        .rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(rd_data),.rd_valid(rd_valid),
        .lookup_addr(32'd0),.lookup_crc(),.lookup_valid(),
        .bad_addr(bad_addr),.bad_expected(bad_expected),.bad_actual(bad_actual),
        .last_read_word(last_read_word),.fail_cnt(fail_cnt),
        .source_words(source_words),.checked_blocks(checked_blocks));

    reg [31:0] mem[0:600000];
    wire [31:0] rd_word=rd_addr>>2;
    function [31:0] pixdata(input [31:0] a); pixdata=a^32'h5A5A_1234; endfunction

    integer wcount,col,r;
    integer errors=0;
    reg [31:0] cur_addr;

    // 读侧响应器：req 后一拍 ack，然后连续给 64 个字
    always @(posedge clk) begin
        rd_ack<=1'b0; rd_valid<=1'b0;
        if(rd_req&&!rd_ack&&!rd_valid) rd_ack<=1'b1;
        else if(rd_ack) begin
            for(r=0;r<BLOCK_WORDS;r=r+1) begin
                @(posedge clk); rd_valid<=1'b1; rd_data<=mem[rd_word+r];
            end
            @(posedge clk); rd_valid<=1'b0;
        end
    end

    task write_frame;
        begin
            frame_slot<=1; frame_begin<=1; @(posedge clk); frame_begin<=0;
            cur_addr=SLOT1+(WORDS-ROW_WORDS)*4; col=0;
            for(wcount=0;wcount<WORDS;wcount=wcount+1)begin
                @(posedge clk);
                write_addr<=cur_addr; write_data<=pixdata(cur_addr); accepted<=1;
                mem[cur_addr>>2]<=pixdata(cur_addr);
                if(col==ROW_WORDS-1)begin col=0; cur_addr=cur_addr-ROW_WORDS*8+4; end
                else begin col=col+1; cur_addr=cur_addr+4; end
            end
            @(posedge clk); accepted<=0; repeat(4)@(posedge clk);
        end
    endtask

    task verify_and_wait;
        begin
            @(posedge clk); verify_start<=1; @(posedge clk); verify_start<=0;
            fork
                begin wait(verify_done==1'b1); end
                begin #80_000_000; end
            join_any
            repeat(4)@(posedge clk);
        end
    endtask

    task do_reset;
        begin
            rst_n<=0; accepted<=0; verify_start<=0; frame_begin<=0;
            repeat(6)@(posedge clk); rst_n<=1; repeat(3)@(posedge clk);
        end
    endtask

    // 把一个块内的所有字都改掉（模拟"该块读回全错"）
    task corrupt_block(input [31:0] blkbase);
        integer k;
        begin
            for(k=0;k<BLOCK_WORDS;k=k+1) mem[(blkbase>>2)+k] = mem[(blkbase>>2)+k] ^ 32'h0000_0001;
        end
    endtask

    initial begin
        rst_n=0; repeat(5)@(posedge clk); rst_n=1; repeat(2)@(posedge clk);

        // ================= 用例 A：只破坏第 0 块 word 5 =================
        write_frame;
        mem[(SLOT1>>2)+5] = mem[(SLOT1>>2)+5] ^ 32'h0000_0001;
        verify_and_wait;
        $display("");
        $display("===== CASE A: corrupt block0 word5 (word0 intact) =====");
        $display("  verify_done=%0d verify_pass=%0d fault=%0d",verify_done,verify_pass,fault);
        $display("  fail_cnt      =%0d  (expect 1)",fail_cnt);
        $display("  checked_blocks=%0d  (expect %0d)",checked_blocks,BLOCKS-1);
        $display("  bad_addr      =%08X (expect %08X = slot base)",bad_addr,SLOT1);
        $display("  EXP(word0)    =%08X (expect %08X)",bad_expected,pixdata(SLOT1));
        $display("  GOT(word1)    =%08X (expect %08X)",bad_actual,pixdata(SLOT1+4));
        $display("  last_read_word=%08X (expect %08X = block0 word0, read last)",
                 last_read_word,pixdata(SLOT1));
        if(fail_cnt!==1)          begin errors=errors+1; $display("  [FAIL] fail_cnt"); end
        if(checked_blocks!==BLOCKS-1) begin errors=errors+1; $display("  [FAIL] checked_blocks"); end
        if(bad_addr!==SLOT1)      begin errors=errors+1; $display("  [FAIL] bad_addr"); end
        if(bad_expected!==pixdata(SLOT1))   begin errors=errors+1; $display("  [FAIL] EXP"); end
        if(bad_actual!==pixdata(SLOT1+4))   begin errors=errors+1; $display("  [FAIL] GOT"); end
        if(last_read_word!==pixdata(SLOT1)) begin errors=errors+1; $display("  [FAIL] last_read_word"); end

        // ================= 用例 B：只破坏末块 word 0 =================
        do_reset;
        write_frame;
        mem[(LASTB>>2)] = mem[(LASTB>>2)] ^ 32'h0000_0001;
        verify_and_wait;
        $display("");
        $display("===== CASE B: corrupt LAST block word0 =====");
        $display("  fail_cnt      =%0d  (expect 1)",fail_cnt);
        $display("  bad_addr      =%08X (expect %08X = last block base)",bad_addr,LASTB);
        $display("  EXP(word0)    =%08X (expect corrupted word)",bad_expected);
        $display("  last_read_word=%08X (expect %08X = block0 word0 intact)",
                 last_read_word,pixdata(SLOT1));
        if(fail_cnt!==1)     begin errors=errors+1; $display("  [FAIL] fail_cnt"); end
        if(bad_addr!==LASTB) begin errors=errors+1; $display("  [FAIL] bad_addr"); end
        if(last_read_word!==pixdata(SLOT1)) begin errors=errors+1; $display("  [FAIL] last_read_word"); end

        // ================= 用例 C：破坏 3 块 =================
        do_reset;
        write_frame;
        corrupt_block(SLOT1+100*BLOCK_WORDS*4);      // 中间块
        corrupt_block(SLOT1+200*BLOCK_WORDS*4);      // 中间块
        corrupt_block(LASTB);                        // 反向首块
        verify_and_wait;
        $display("");
        $display("===== CASE C: corrupt 3 blocks (200, 100, 2399) =====");
        $display("  fail_cnt      =%0d  (expect 3)",fail_cnt);
        $display("  bad_addr      =%08X (expect %08X = first verified = last block)",
                 bad_addr,LASTB);
        if(fail_cnt!==3)     begin errors=errors+1; $display("  [FAIL] fail_cnt"); end
        if(bad_addr!==LASTB) begin errors=errors+1; $display("  [FAIL] bad_addr"); end

        $display("");
        $display("  RESULT: %0d error(s)", errors);
        $finish;
    end
endmodule
