`timescale 1ns/1ps
module tb_pattern_generator;
    reg rst_n=1,de=1,right=1;reg [11:0] x=0,y=0;reg [2:0] sel=0;
    wire [23:0] base,hd;
    pattern_generator b(.rst_n(rst_n),.de(de),.x(x),.y(y),.pattern_select(sel),.arrow_right(right),.rgb(base));
    pattern_generator #(.H_ACTIVE(1280),.V_ACTIVE(720)) h(.rst_n(rst_n),.de(de),.x(x),.y(y),.pattern_select(sel),.arrow_right(right),.rgb(hd));
    function [23:0] expected(input integer px,py,w,h,m,input  dir);
        integer xx,dy,segment;
        reg inside_arrow;
        begin
            dir = (dir === 1'b1); expected=0;
            if(rst_n && de && px<w && py<h) begin
                case(m)
                    0: expected=24'hff0000;
                    1: expected=(px<w/3) ? 24'hff0000:(px<(w*2)/3) ? 24'h00ff00:24'h0000ff;
                    2: expected=(((px/32)+(py/32))%2) ? 24'hffffff:0;
                    3: expected=(px>=100 && px<400 && py>=200 && py<300) ? 24'h00ff00:0;
                    4: begin

                        xx=dir ? px:(w-1-px); dy=py-h/2;
                        inside_arrow= (((xx>=w/2-64 && xx<w/2+16 && dy>=-16 && dy<16)) === 1'b1);
                        if(xx>=w/2 && xx<w/2+64) begin
                            segment=(xx-w/2)/16;
                            inside_arrow= ((inside_arrow || (dy>=-(64-segment*16) && dy<(64-segment*16))) === 1'b1);
                        end
                        expected=inside_arrow ? 24'hffff00:0;
                    end
                    5: expected=(px==0 || py==0 || px==w-1 || py==h-1) ? 24'hffffff:0;
                    default: expected=0;
                endcase
            end

     end endfunction
    integer checks=0,m,i,j,d;
    task verify;
        begin  #1;
            checks = checks + (2);
            if(base !== expected(x,y,640,480,sel,right) || hd !== expected(x,y,1280,720,sel,right))
                begin $display("[FAIL] pattern m=%d dir=%b x=%d y=%d base=%h hd=%h",sel,right,x,y,base,hd); $finish; end

     end endtask
    initial begin
        for(m=0;m<6;m = m + 1) begin
            sel=m;
            for(d=0;d<((m==4) ? 2:1);d = d + 1) begin
                right=d;
                for(j=0;j<721;j = j + 1) for(i=0;i<1281;i = i + 1) begin x=i;y=j;verify();end
            end
        end
        sel=7;x=20;y=20;verify(); sel=0;de=0;verify();de=1;rst_n=0;verify();
        $display("PASS tb_pattern_generator: %0d checks",checks);$finish;
    end
    initial begin #7000000;begin $display("[FAIL] tb_pattern_generator watchdog"); $finish; end end
endmodule
