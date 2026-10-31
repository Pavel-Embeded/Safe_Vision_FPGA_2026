`timescale 1ns/1ps
module tb_a_pixel_fifo;
    reg wc=0,rc=0,rst=1,we=0,re=0;
    reg [31:0] din=0;
    wire [15:0] dout;
    wire full,af,ready,valid,empty,ae;
    wire [5:0] words;wire [6:0] pixels;
    integer head=0,tail=0,wr=0,rd=0,ticks=0,phase=0,checks=0;
    reg [15:0] expected[0:32767];
    always #4 wc=~wc;
    initial begin #2.301;forever #6.733 rc=~rc;end
    a_pixel_fifo #(.AW(6)) dut(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(din),.wr_en(we),
      .full(full),.almost_full(af),.wr_words(words),.wr_ready(ready),.rd_en(re),
      .rd_data(dout),.rd_valid(valid),.empty(empty),.almost_empty(ae),.rd_pixels(pixels));
    always @(posedge wc)if(!rst)begin
        if(we&&ready&&!full)begin expected[tail]=din[15:0];expected[tail+1]=din[31:16];tail=tail+2;wr=wr+1;end
        if(words>63)begin $display("[FAIL] FIFO write count exceeds capacity"); $finish; end
    end
    always @(posedge rc)if(!rst)begin
        if(re&&!empty&&valid)begin
            if(head>=tail)begin $display("[FAIL] FIFO output without accepted input"); $finish; end
            if(dout!==expected[head])begin $display("[FAIL] FIFO order/halfword head=%0d got=%h expected=%h",head,dout,expected[head]); $finish; end
            head=head+1;rd=rd+1;checks=checks+1;
        end
        if(valid!==!empty)begin $display("[FAIL] FIFO FWFT valid/empty contract"); $finish; end
        if(pixels>126)begin $display("[FAIL] FIFO read count exceeds capacity"); $finish; end
    end
    always @(negedge wc)if(!rst)begin
        ticks=ticks+1;
        din={v_cast_s16(wr*2+1),v_cast_s16(wr*2)};
        if(phase==1)we=1;
        else if(phase==2)we=((0 + (($unsigned($random)) % ((3)-(0)+1)))!=0)&&ticks<7000;
        else we=0;
    end
    always @(negedge rc)if(!rst)re=(phase==2) ? ((0 + (($unsigned($random)) % ((4)-(0)+1)))!=0):(phase==3);
    task reset_epoch;
        begin  rst=1;we=0;re=0;#23;head=0;tail=0;wr=0;rd=0;ticks=0;rst=0;repeat(10)@(negedge wc);
     end endtask
    initial begin
        reset_epoch();phase=1;
        wait(full);repeat(10)@(negedge wc);
        if(tail!=126||!af)begin $display("[FAIL] FIFO capacity/full wrong tail=%0d af=%b",tail,af); $finish; end
        phase=3;wait(empty);repeat(12)@(negedge rc);
        if(head!=tail||pixels!=0||!ae)begin $display("[FAIL] FIFO drain/empty count"); $finish; end
        phase=2;wait(ticks>=7000);phase=3;wait(empty);repeat(12)@(negedge rc);
        if(head!=tail||checks<3000)begin $display("[FAIL] FIFO random/wrap coverage"); $finish; end
        phase=1;repeat(25)@(negedge wc);reset_epoch();
        phase=2;wait(ticks>=7000);phase=3;wait(empty);repeat(12)@(negedge rc);
        if(head!=tail)begin $display("[FAIL] FIFO reset epoch stale data"); $finish; end
        $display("PASS tb_a_pixel_fifo: checks=%0d actual TD FIFO/RAM, async clocks, 32/16 low-first, capacity126, stalls, wrap, counts, reset",checks);$finish;
    end
    initial begin #300000;begin $display("[FAIL] FIFO watchdog"); $finish; end end

function signed [15:0] v_cast_s16; input signed [15:0] value; begin  v_cast_s16=value;   end endfunction
endmodule
