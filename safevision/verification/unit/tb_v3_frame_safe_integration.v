`timescale 1ns/1ps
module tb_v3_frame_safe_integration;
 reg clk=0,rst=0,request=0;always #5 clk=~clk;
 reg[11:0]rx=0,ry=0;reg rd=0;integer lx=0,ly=0,cycle=0,trial,i,errors=0,comparisons=0;
 wire[11:0]x,y;wire[23:0]rgb;wire de;reg[23:0]frame_rgb=0;reg raw_frame_safe=1,seen=0;
 v3_video_display_core #(.HANDBOOK_PROFILE(1),.PACKED_CACHE(1),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.STATUS_TEXT_FILE("v3_handbook_status_text.mem")) d(
 .sys_clk(clk),.mem_clk(clk),.pixel_clk(clk),.sys_rst_n(rst),.mem_rst_n(rst),.pixel_rst_n(rst),
 .media_reset(1'b0),.cfg_valid(1'b0),.cfg_data(99'd0),.cache_valid(4'hf),.next_request(1'b0),.safety_active(1'b0),
 .media_ready(1'b0),.media_ready_generation(8'd0),.rd_ack(1'b0),.rd_busy(1'b0),.rd_data(32'd0),.rd_valid(1'b0),
 .lookup_crc(32'd0),.lookup_valid(1'b0),.x(x),.y(y),.rgb(rgb),.de(de));
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<12)$display("[FAIL] %s",msg);end end  end endtask
 always@(negedge clk)begin
  if(!rst)begin lx=0;ly=0;cycle=0;end
  else begin cycle = cycle + 1;if(lx==31)begin lx=0;ly=(ly==5) ? 0:ly+1;end else lx = lx + 1;end
  rx=lx;ry=(ly<4) ? ly:480+ly-4;rd=lx<24&&ly<4;
 end
 always@(posedge clk)begin #0.001;if(rst)begin
  if(de)begin
   ck(rgb===24'hff0000||rgb===24'h0000ff,"final21-cycle output selects a valid supplied source");
   if(x==0&&y==0)begin frame_rgb=rgb;seen=1;end
   else if(seen)ck(rgb===frame_rgb,"actual production output mux never mixes normal/SAFE within active frame");
  end
  if(rd)begin
   if(rx==0&&ry==0)raw_frame_safe=d.graphics.safety_active;
   else ck(d.graphics.safety_active===raw_frame_safe,"graphics safety state remains aligned with source frame");
  end
 end end
 task normal_frame;
  begin begin request=0;wait(!d.frame_safe_raw&&!d.frame_safe_output);wait(de&&x==0&&y==0&&rgb==24'h0000ff);end
  end endtask
 initial begin


  force d.raw_x=rx;force d.raw_y=ry;force d.raw_de=rd;
  force d.safe_p2=request;force d.media_p2=0;force d.fault_p2=0;force d.presentation_fault_p=0;
  force d.enabled=1;force d.missing_tags=0;
  force d.o3=16'h001f;force d.safe_pixel4=16'hf800;
  repeat(4)@(negedge clk);rst=1;
  for(trial=0;trial<100;trial = trial + 1)begin
   normal_frame();repeat((trial*37)%192)@(negedge clk);request=1;
   wait(de&&rgb==24'hff0000&&x==0&&y==0);repeat(128)@(negedge clk);
  end
  if(errors==0)$display("[PASS] actual video core mux,21-cycle tag/SAFE source alignment,100 varied assertion phases and frame-stable graphics state");
  $display("[TB] tb_v3_frame_safe_integration done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #2000000;$display("[FAIL] integration watchdog");$display("[TB] tb_v3_frame_safe_integration done errors=1");$finish;end
endmodule
