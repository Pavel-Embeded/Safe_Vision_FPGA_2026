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
        if(words>63)$fatal(1,"FIFO write count exceeds capacity");
    end
    always @(posedge rc)if(!rst)begin
        if(re&&!empty&&valid)begin
            if(head>=tail)$fatal(1,"FIFO output without accepted input");
            if(dout!==expected[head])$fatal(1,"FIFO order/halfword head=%0d got=%h expected=%h",head,dout,expected[head]);
            head=head+1;rd=rd+1;checks=checks+1;
        end
        if(valid!==!empty)$fatal(1,"FIFO FWFT valid/empty contract");
        if(pixels>126)$fatal(1,"FIFO read count exceeds capacity");
    end
    always @(negedge wc)if(!rst)begin
        ticks=ticks+1;
        din={16'(wr*2+1),16'(wr*2)};
        if(phase==1)we=1;
        else if(phase==2)we=($urandom_range(0,3)!=0)&&ticks<7000;
        else we=0;
    end
    always @(negedge rc)if(!rst)re=(phase==2)?($urandom_range(0,4)!=0):(phase==3);
    task reset_epoch;
        begin rst=1;we=0;re=0;#23;head=0;tail=0;wr=0;rd=0;ticks=0;rst=0;repeat(10)@(negedge wc);end
    endtask
    initial begin
        reset_epoch();phase=1;
        wait(full);repeat(10)@(negedge wc);
        if(tail!=126||!af)$fatal(1,"FIFO capacity/full wrong tail=%0d af=%b",tail,af);
        phase=3;wait(empty);repeat(12)@(negedge rc);
        if(head!=tail||pixels!=0||!ae)$fatal(1,"FIFO drain/empty count");
        phase=2;wait(ticks>=7000);phase=3;wait(empty);repeat(12)@(negedge rc);
        if(head!=tail||checks<3000)$fatal(1,"FIFO random/wrap coverage");
        phase=1;repeat(25)@(negedge wc);reset_epoch();
        phase=2;wait(ticks>=7000);phase=3;wait(empty);repeat(12)@(negedge rc);
        if(head!=tail)$fatal(1,"FIFO reset epoch stale data");
        $display("PASS tb_a_pixel_fifo: checks=%0d actual TD FIFO/RAM, async clocks, 32/16 low-first, capacity126, stalls, wrap, counts, reset",checks);$finish;
    end
    initial begin #300000;$fatal(1,"FIFO watchdog");end
endmodule
