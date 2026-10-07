`timescale 1ns/1ps
`include "safevision_defs.vh"

// Default 640x480 geometry. A per-edge invariant checks the registered full
// predicate against the original counter equality, including stalls, frame
// completion, overflow, rejected starts, new frames and asynchronous reset.
// Every accepted write is also checked against an independent pixel/address
// oracle; neither the writer's counter nor its full flag drives that oracle.
module tb_frame_writer_full_flag_equivalence;
    localparam integer PIXELS = 640*480;
    localparam integer WORDS = PIXELS/2;
    reg clk=0, rst_n=0, start=0;
    always #4 clk=~clk;
    reg [1:0] slot_sel=0;
    reg [31:0] slot_base=0;
    reg [15:0] din=0;
    reg din_valid=0, wr_ready=0;
    wire din_ready,wr_req,wr_done,crc_ok,wr_error;
    wire [31:0] wr_addr,wr_data;
    wire [15:0] wr_len,crc_value;
    wire [3:0] slot_valid;
    wire [18:0] px_cnt;
    wire [7:0] err_code,err_detail;
    frame_writer dut(.clk(clk),.rst_n(rst_n),.start(start),
        .slot_sel(slot_sel),.slot_base(slot_base),.din(din),.din_valid(din_valid),
        .din_ready(din_ready),.wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),
        .wr_len(wr_len),.wr_ready(wr_ready),.wr_done(wr_done),
        .slot_valid(slot_valid),.crc_ok(crc_ok),.crc_value(crc_value),
        .px_cnt(px_cnt),.wr_error(wr_error),.err_code(err_code),.err_detail(err_detail));

    integer checks=0,invariant_edges=0,pixels_seen=0,words_seen=0,done_seen=0;
    integer stalled_edges=0;
    reg phase_active=0,previous_stall=0;
    reg [31:0] expected_base=0,previous_addr=0,previous_data=0;
    reg [15:0] pattern_seed=16'h73a5,expected_crc=0;
    reg [31:0] ready_lfsr=32'h13579bdf;

    function automatic [15:0] pixel_at(input integer n);
        pixel_at=(n*19)^(n>>8)^pattern_seed;
    endfunction
    function automatic [15:0] crc_byte(input [15:0] prior,input [7:0] value);
        reg [15:0] c;
        integer b;
        begin
            c=prior^{value,8'h00};
            for(b=0;b<8;b=b+1)c=c[15]?((c<<1)^16'h1021):(c<<1);
            crc_byte=c;
        end
    endfunction
    function automatic [15:0] crc_word(input [15:0] prior,input [31:0] value);
        reg [15:0] c;
        begin
            c=crc_byte(prior,value[31:24]);c=crc_byte(c,value[23:16]);
            c=crc_byte(c,value[15:8]);crc_word=crc_byte(c,value[7:0]);
        end
    endfunction
    task automatic check(input bit condition,input string label);
        begin
            checks=checks+1;
            if(!condition)$fatal(1,"[FAIL] %s at %t",label,$time);
            $display("[PASS] %s",label);
        end
    endtask

    // Fixed seed and actual backpressure; a stalled word must remain stable.
    always @(negedge clk)begin
        if(!rst_n)begin ready_lfsr=32'h13579bdf;wr_ready=0;end
        else begin
            ready_lfsr={ready_lfsr[30:0],ready_lfsr[31]^ready_lfsr[21]^ready_lfsr[1]^ready_lfsr[0]};
            wr_ready=ready_lfsr[0]||ready_lfsr[4];
        end
    end
    always @(posedge clk)begin
        if(rst_n&&phase_active)begin
            if(previous_stall&&(wr_req!==1'b1||wr_addr!==previous_addr||wr_data!==previous_data))
                $fatal(1,"[FAIL] write changed while stalled");
            if(din_valid&&din_ready)begin
                if(pixels_seen>=PIXELS||din!==pixel_at(pixels_seen))
                    $fatal(1,"[FAIL] pixel acceptance oracle n=%0d",pixels_seen);
                pixels_seen=pixels_seen+1;
            end
            if(wr_req&&wr_ready)begin
                if(words_seen>=WORDS||wr_len!==16'd1||wr_addr!==(expected_base+words_seen*4)||
                   wr_data!=={pixel_at(words_seen*2+1),pixel_at(words_seen*2)})
                    $fatal(1,"[FAIL] write oracle word=%0d addr=%h data=%h",words_seen,wr_addr,wr_data);
                if((words_seen%1024)==0)expected_crc=crc_word(expected_crc,wr_data);
                words_seen=words_seen+1;
            end
            if(wr_done)begin
                done_seen=done_seen+1;
                if(pixels_seen!=PIXELS||words_seen!=WORDS||crc_value!==expected_crc)
                    $fatal(1,"[FAIL] early completion or independent CRC mismatch");
            end
            previous_stall=wr_req&&!wr_ready;
            if(previous_stall)begin
                previous_addr=wr_addr;previous_data=wr_data;stalled_edges=stalled_edges+1;
            end
        end else previous_stall=0;
    end
    // Sample after nonblocking updates, so a one-cycle late flag is rejected
    // immediately at the final pixel, rather than hidden by the test driver.
    always @(posedge clk)begin
        #1;
        invariant_edges=invariant_edges+1;
        if(dut.frame_full !== (px_cnt==19'd307200))
            $fatal(1,"[FAIL] full flag/equality differ count=%0d flag=%b at %t",px_cnt,dut.frame_full,$time);
        if(dut.frame_full&&din_ready)$fatal(1,"[FAIL] ready remained high after full");
    end

    task automatic begin_frame(input [1:0] selected,input [31:0] base,input [15:0] seed);
        begin
            @(negedge clk);phase_active=0;din_valid=0;
            slot_sel=selected;slot_base=base;pattern_seed=seed;expected_base=base;
            pixels_seen=0;words_seen=0;done_seen=0;expected_crc=0;previous_stall=0;
            start=1;phase_active=1;
            @(posedge clk);#2;
            check(px_cnt==0&&!dut.frame_full&&!wr_error,"accepted start clears counter and full together");
            @(negedge clk);start=0;
        end
    endtask
    task automatic send_pixels(input integer requested);
        integer n;
        begin
            n=0;
            @(negedge clk);din_valid=1;din=pixel_at(0);
            while(n<requested&&!wr_error)begin
                @(posedge clk);
                if(din_valid&&din_ready)n=n+1;
                @(negedge clk);
                if(n<requested)din=pixel_at(n);else din_valid=0;
            end
            din_valid=0;
        end
    endtask
    task automatic pulse_reset;
        begin
            @(negedge clk);phase_active=0;din_valid=0;start=0;
            #1;rst_n=0;#1;
            check(px_cnt==0&&!dut.frame_full&&slot_valid==0,"asynchronous reset clears full/counter/slot-valid");
            repeat(4)@(negedge clk);
            rst_n=1;
            repeat(2)@(negedge clk);
        end
    endtask

    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        begin_frame(0,`SV_IMG0_BASE,16'h73a5);
        send_pixels(PIXELS);
        repeat(12)@(negedge clk);
        check(pixels_seen==PIXELS&&words_seen==WORDS,"complete default frame: every pixel/153600 write words correct");
        check(done_seen==1&&crc_ok&&slot_valid[0]&&!wr_error&&px_cnt==PIXELS&&dut.frame_full,
              "exact-length frame completes once with CRC and valid slot");
        check(stalled_edges>1000,"word stability checked under deterministic backpressure");

        // A rejected start did not clear px_cnt in the original implementation.
        // Retaining full here is essential to exact reachable-state equivalence.
        phase_active=0;
        @(negedge clk);slot_base=32'h003f0000;start=1;
        @(posedge clk);#2;
        check(wr_error&&err_detail==`DET_BMP_TRUNC&&!wr_req&&px_cnt==PIXELS&&dut.frame_full,
              "rejected illegal start retains counter/full and emits no write");
        @(negedge clk);start=0;

        begin_frame(1,`SV_IMG1_BASE,16'hc14f);
        send_pixels(PIXELS+1);
        repeat(8)@(negedge clk);
        check(pixels_seen==PIXELS&&words_seen==WORDS&&done_seen==0,
              "extra pixel is rejected after exactly one complete frame of writes");
        check(wr_error&&err_code==`ERR_MEDIA_INVALID&&err_detail==`DET_BMP_SIZE&&
              !crc_ok&&!slot_valid[1]&&px_cnt==PIXELS&&dut.frame_full,
              "overflow reports size error without publishing the new slot");

        pulse_reset();
        begin_frame(2,`SV_IMG2_BASE,16'h529e);
        send_pixels(17);
        repeat(4)@(negedge clk);
        check(px_cnt==17&&!dut.frame_full&&pixels_seen==17&&words_seen==8,
              "partial odd-pixel frame stays non-full before reset");
        pulse_reset();
        begin_frame(3,`SV_IMG3_BASE,16'h8b06);
        send_pixels(6);
        repeat(4)@(negedge clk);
        check(pixels_seen==6&&words_seen==3&&px_cnt==6&&!dut.frame_full&&!wr_error,
              "post-reset frame has no stale half-pixel or pending write");
        check(invariant_edges>900000,"full flag equals original predicate on every sampled edge");
        $display("[PASS] frame full equivalence checks=%0d invariant_edges=%0d stall_edges=%0d",checks,invariant_edges,stalled_edges);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1,"[FAIL] full flag equivalence watchdog");
    end
endmodule
