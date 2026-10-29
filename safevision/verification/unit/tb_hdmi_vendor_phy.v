

`timescale 1ns/1ps
module hdmi_phy_fixture #(parameter integer HD=0)(output reg done);
 initial begin done = 0; end

    localparam real SH=HD ? 1.347:3.972;
    reg serial_clk=0,pixel_clk=0,rst=1;
    always #SH serial_clk=~serial_clk;
    always #(5*SH) pixel_clk=~pixel_clk;
    reg [9:0] a=0,b=0,c=0,d=0;wire [3:0] q;
    hdmi_phy_wrapper dut(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst),
        .I_tmds_channel_0(a),.I_tmds_channel_1(b),.I_tmds_channel_2(c),.I_tmds_channel_clk(d),
        .O_tmds_ch0_p(q[0]),.O_tmds_ch1_p(q[1]),.O_tmds_ch2_p(q[2]),.O_tmds_clk_p(q[3]));
    function [9:0] word_value(input integer n,lane);
        reg [9:0] v;
        begin begin v=(n*73+lane*137)^((n>>3)*19);word_value=v;end
     end endfunction
    reg capture=0;reg [3:0] captured[0:10999];integer used=0;
    always @(serial_clk)begin
        #0.2;
        if(capture)begin
            if(used>=11000)begin $display("[FAIL] capture overflow"); $finish; end 
            captured[used]=q;used=used+1;
        end
    end
    integer n,lane,offset,bitno,epoch,matched,total;reg good;reg [9:0] expected;
    initial begin
        for(epoch=0;epoch<2;epoch=epoch+1)begin
            rst=1;capture=0;used=0;a=0;b=0;c=0;d=0;
            repeat(12)@(negedge pixel_clk);rst=0;
            repeat(12)@(negedge pixel_clk);
            capture=1;
            for(n=0;n<1024;n=n+1)begin
                a=word_value(n,0);b=word_value(n,1);c=word_value(n,2);d=word_value(n,3);
                @(negedge pixel_clk);
            end
            repeat(12)@(negedge pixel_clk);capture=0;
            matched=-1;
            for(offset=0;offset<120;offset=offset+1)begin
                good=1;
                for(n=0;n<1024&&good;n=n+1)begin
                    for(lane=0;lane<4&&good;lane=lane+1)begin
                        expected=word_value(n,lane);
                        for(bitno=0;bitno<10;bitno=bitno+1)
                            if(captured[offset+n*10+bitno][lane]!==expected[bitno])good=0;
                    end
                end
                if(good)matched=offset;
            end
            if(matched<0)begin $display("[FAIL] official PHY bit sequence mismatch HD=%0d epoch=%0d",HD,epoch); $finish; end 
            $display("PASS actual vendor PHY HD=%0d epoch=%0d offset=%0d bits=40960",HD,epoch,matched);
        end
        done=1;
    end
endmodule
module tb_hdmi_vendor_phy;
    wire a,b;hdmi_phy_fixture #(.HD(0)) base(a);hdmi_phy_fixture #(.HD(1)) hd(b);
    initial begin wait(a&&b);$display("PASS tb_hdmi_vendor_phy");$finish;end
    initial begin #1000000;begin $display("[FAIL] PHY watchdog"); $finish; end end
endmodule
