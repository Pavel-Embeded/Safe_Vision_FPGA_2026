`timescale 1ns/1ps
module fps_boundary_case #(parameter HZ=256)(input clk,output reg done=0,output integer errors=0,comparisons=0);
 reg rst=0,fs=0;integer tick=0,total_frames=0,expected=0,observed_sum=0,i,phase;
 v3_status_layers #(.PIXEL_HZ(HZ),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_status_text.mem")) dut(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(12'd0),.raw_y(12'd0),.raw_de(1'b0),.frame_start(fs),.cfg_data(96'd0),.cache_valid(4'd0),.underflows(32'd0),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0));
 always @(posedge clk)if(rst)begin
  observed_sum=total_frames+(fs?1:0);
  if(tick==HZ-1)begin expected=observed_sum>255?255:observed_sum;total_frames=0;tick=0;end
  else begin total_frames=observed_sum;tick=tick+1;end
  #1;comparisons=comparisons+1;
  if(dut.fps!==expected[7:0])begin errors=errors+1;if(errors<8)$display("[FAIL] HZ=%0d tick=%0d count=%0d got=%0d expected=%0d",HZ,tick,total_frames,dut.fps,expected);end
 end
 initial begin
  repeat(3)@(negedge clk);rst=1;
  for(i=0;i<8*HZ;i=i+1)begin
   phase=i/HZ;
   case(phase)
    0,1:fs=1;
    2:fs=(i%17==0)||(i%HZ==HZ-1);
    3:fs=0;
    4:fs=(i%HZ<255)||(i%HZ==HZ-1);
    5:fs=(i%HZ<255);
    6:fs=i%HZ==HZ-1;
    default:fs=((i*37+19)%31<11)||(i%HZ==HZ-1);
   endcase
   @(negedge clk);
  end
  fs=0;repeat(3)@(negedge clk);done=1;
 end
endmodule
module tb_v3_fps_boundary;
 reg clk=0;always #5 clk=~clk;wire d0,d1,d2,d3;wire[31:0] e0,e1,e2,e3,c0,c1,c2,c3;integer errors,comparisons;
 fps_boundary_case #(.HZ(256)) a(clk,d0,e0,c0);fps_boundary_case #(.HZ(512)) b(clk,d1,e1,c1);
 fps_boundary_case #(.HZ(257)) c(clk,d2,e2,c2);fps_boundary_case #(.HZ(1)) d(clk,d3,e3,c3);
 initial begin wait(d0&&d1&&d2&&d3);#2;errors=e0+e1+e2+e3;comparisons=c0+c1+c2+c3;
 if(errors==0)$display("[PASS] independent non-saturating frame oracle, full-boundary carry, exact255, empty windows, power-of-two timers and HZ1");
 $display("[TB] tb_v3_fps_boundary done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #100000;$display("[FAIL] FPS boundary watchdog errors=1");$finish;end
endmodule
