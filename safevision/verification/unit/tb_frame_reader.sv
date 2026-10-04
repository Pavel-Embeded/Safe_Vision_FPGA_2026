`timescale 1ns/1ps
module reader_case #(parameter W=640,H=480,HP=16,HS=96,HB=48,VP=10,VS=2,VB=33)(output reg done=0);
 reg clk=0,rst=0; always #2 clk=~clk;
 wire [11:0] x,y,xo,yo;wire hs,vs,de,ls,fs,afs,hb,vb;
 video_timing #(.H_ACTIVE(W),.H_FRONT(HP),.H_SYNC(HS),.H_BACK(HB),.V_ACTIVE(H),.V_FRONT(VP),.V_SYNC(VS),.V_BACK(VB)) scan(
 .clk(clk),.rst_n(rst),.x(x),.y(y),.hsync(hs),.vsync(vs),.de(de),.line_start(ls),.frame_start(fs),.active_frame_start(afs),.hblank(hb),.vblank(vb));
 integer frame=0,position=0,checks=0; reg fault_ref=0; integer faults=0;
 wire empty=(frame==1&&x==33&&y==4);wire re;wire [23:0] rgb;wire valid,ho,vo,deo,lso,fso,afso,hbo,vbo,fault,pulse;wire [31:0] count;
 function [15:0] pattern(input integer p);pattern=(p*17)^(p>>9)^16'h4b93;endfunction
 function [23:0] expand(input [15:0] p);expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};endfunction
 frame_reader #(.IMAGE_W(W),.IMAGE_H(H),.UNDERFLOW_COLOR(24'h987654)) dut(
 .clk(clk),.rst_n(rst),.image_enable(1'b1),.stream_armed(1'b1),.fifo_data(pattern(position)),.fifo_valid(!empty),.fifo_empty(empty),.fifo_rd_en(re),
 .x_in(x),.y_in(y),.hsync_in(hs),.vsync_in(vs),.de_in(de),.line_start_in(ls),.frame_start_in(fs),.active_frame_start_in(afs),.hblank_in(hb),.vblank_in(vb),
 .rgb_out(rgb),.x_out(xo),.y_out(yo),.hsync_out(ho),.vsync_out(vo),.de_out(deo),.pixel_valid_out(valid),.line_start_out(lso),.frame_start_out(fso),.active_frame_start_out(afso),.hblank_out(hbo),.vblank_out(vbo),.frame_fault(fault),.underflow_pulse(pulse),.underflow_count(count));
 reg [31:0] tags;reg [23:0] want;reg vr,pr;integer oldf;
 always @(posedge clk)if(rst&&!done)begin
   tags={x,y,hs,vs,de,ls,fs,afs,hb,vb};vr=de&&!fault_ref&&!empty;
   want=!de?24'd0:(vr?expand(pattern(position)):24'h987654);
   if(re!==vr)$fatal(1,"reader read enable W=%0d f=%0d x=%0d y=%0d",W,frame,x,y);
   if(re)begin
     if(position!=y*W+x)$fatal(1,"reader order W=%0d f=%0d pos=%0d xy=%0d",W,frame,position,y*W+x);
     position=position+1;
   end
   pr=de&&!fault_ref&&empty;
   if(fs)fault_ref=0;else if(pr)begin fault_ref=1;faults=faults+1;end
   oldf=frame;
   if(x==W+HP+HS+HB-1&&y==H+VP+VS+VB-1)begin frame=frame+1;position=0;end
   #0.1;
   if({xo,yo,ho,vo,deo,lso,fso,afso,hbo,vbo}!==tags||rgb!==want||valid!==vr||fault!==fault_ref||pulse!==pr||count!==faults)
     $fatal(1,"reader score W=%0d f=%0d tags=%h/%h rgb=%h/%h valid=%b/%b fault=%b/%b",W,oldf,{xo,yo,ho,vo,deo,lso,fso,afso,hbo,vbo},tags,rgb,want,valid,vr,fault,fault_ref);
   checks=checks+1;
   if(frame==3)begin done=1;$display("reader W=%0d H=%0d checks=%0d underflows=%0d",W,H,checks,faults);end
 end
 initial begin repeat(4)@(negedge clk);rst=1;end
endmodule
module tb_frame_reader;
 wire d0,d1;
 reader_case a(d0);
 reader_case #(.W(1280),.H(720),.HP(110),.HS(40),.HB(220),.VP(5),.VS(5),.VB(20)) b(d1);
 initial begin wait(d0&&d1);$display("PASS tb_frame_reader: BASE+HD three complete frames, pixel order, tags, underflow and recovery");$finish;end
 initial begin #20000000;$fatal(1,"reader timeout");end
endmodule
