`timescale 1ns/1ps
module tb_video_stream_cdc;
    reg sc=0,dc=0,rst_n=0;integer sp=3,dp=11;
    always #(sp)sc=~sc;
    initial begin #0.731;forever #(dp)dc=~dc;end
    reg [15:0] in_data=0;reg in_last=0,in_valid=0;wire in_ready;
    wire [15:0] s_data;wire s_last,s_valid,s_ready;
    wire [16:0] d_data;wire d_valid;reg d_ready=0;
    video_stream_slice #(.WIDTH(16)) stream(.clk(sc),.rst_n(rst_n),
      .in_data(in_data),.in_last(in_last),.in_valid(in_valid),.in_ready(in_ready),
      .out_data(s_data),.out_last(s_last),.out_valid(s_valid),.out_ready(s_ready));
    video_cdc_mailbox #(.WIDTH(17)) mailbox(.src_clk(sc),.src_rst_n(rst_n),
      .src_data({s_last,s_data}),.src_valid(s_valid),.src_ready(s_ready),
      .dst_clk(dc),.dst_rst_n(rst_n),.dst_data(d_data),.dst_valid(d_valid),.dst_ready(d_ready));
    integer head=0,tail=0,sent=0,received=0,checks=0,goal=1500;
    reg [16:0] q[0:8191],held;reg stalled=0,source_fire=0;
    always @(posedge sc)source_fire<=rst_n&&in_valid&&in_ready;
    always @(negedge sc)if(rst_n)begin
        if(!in_valid||source_fire)begin
            in_valid=sent<goal && $urandom_range(0,3)!=0;
            in_data=16'(sent*73+17);in_last=(sent%37)==36;
        end
    end
    always @(posedge sc)if(rst_n&&in_valid&&in_ready)begin
        if(in_data!==16'(sent*73+17)||in_last!==((sent%37)==36))$fatal(1,"source sequence/last mismatch");
        q[tail]={in_last,in_data};tail=tail+1;sent=sent+1;
    end
    always @(negedge dc)if(rst_n)d_ready=$urandom_range(0,7)<4;
    always @(posedge dc)if(rst_n)begin
        if(stalled && (!d_valid || d_data!==held))$fatal(1,"CDC data/valid changed on backpressure");
        stalled=d_valid&&!d_ready;held=d_data;
        if(d_valid&&d_ready)begin
            if(head>=tail||d_data!==q[head])$fatal(1,"stream/CDC order head=%0d data=%h expected=%h",head,d_data,q[head]);
            head=head+1;received=received+1;checks=checks+1;
        end
    end else stalled=0;
    task reset_epoch;
        begin rst_n=0;in_valid=0;d_ready=0;#37;head=0;tail=0;sent=0;received=0;stalled=0;rst_n=1;end
    endtask
    initial begin
        reset_epoch();wait(received==goal);repeat(12)@(negedge dc);
        if(sent!=received||d_valid)$fatal(1,"mailbox didn't drain");

        goal=2500;wait(sent>1510);reset_epoch();sp=13;dp=2;goal=1500;
        wait(received==goal);repeat(12)@(negedge dc);
        if(sent!=received||d_valid)$fatal(1,"CDC reset/new clock ratio didn't drain");
        $display("PASS tb_video_stream_cdc: checks=%0d stream+last, stalls, fast/slow domains, common reset epochs",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"stream/CDC watchdog");end
endmodule
