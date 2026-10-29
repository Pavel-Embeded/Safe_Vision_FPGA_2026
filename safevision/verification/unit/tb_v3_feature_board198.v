`timescale 1ns/1ps
module feature_board198 #(parameter HD=0)(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 reg clk=0,rst=0;always #10 clk=~clk;
 safevision_v3_top #(.HD(HD)) dut(.clk(clk),.rst_n(rst),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 defparam dut.uptime.CLK_HZ=50000;
 localparam W=HD ? 1280:640,H=HD ? 720:480;
 integer captured_total=0,i;integer frames=0,saved_time,panel_file,panel_pixels=0;
 reg[3:0] panel_frame[0:20];
 initial panel_file=$fopen("spectrum_panel_rgb888.mem","w");
 reg[23:0] q[0:20];reg[20:0] vq=0;reg[15:0] fg,p565;
 function[15:0]blend(input[15:0]f);integer r,g,b;begin begin
 r=(f[15:11]*224+127)/255;g=(f[10:5]*224+127)/255;b=(f[4:0]*224+127)/255;blend={v_cast_s5(r),v_cast_s6(g),v_cast_s5(b)};end  end endfunction
 function[23:0]expand(input[15:0]p);begin begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end  end endfunction
 task ck(input  ok,input [4095:0] m);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<8)$display("[FAIL] HD%0d %s",HD,m);end end  end endtask
 always@(posedge dut.pixel_clk)begin
  if(!dut.pixel_rst_n)begin vq=0;for(i=0;i<21;i = i + 1)begin q[i]=0;panel_frame[i]=0;end end
  else begin
   if(dut.raw_fs)frames = frames + 1;
   if(dut.pcm_valid)captured_total = captured_total + 1;
   for(i=20;i>0;i = i - 1)begin q[i]=q[i-1];vq[i]=vq[i-1];panel_frame[i]=panel_frame[i-1];end
   panel_frame[0]=frames[3:0];
   vq[0]=dut.raw_de&&dut.raw_x>=W-304&&dut.raw_x<W-16&&dut.raw_y>=H-160&&dut.raw_y<H-36;


   #0.001;
   if(vq[20])ck(dut.video.rgb===q[20],"actual PCM spectrum pixels -> HUD palette -> finalRGB, exact public pipeline");
   if(vq[20]&&panel_frame[20]==3&&panel_file!=0)begin $fdisplay(panel_file,"%06h",dut.video.rgb);panel_pixels = panel_pixels + 1;end
   fg=dut.video.graphics.wave_trace ? dut.video.graphics.wave_colour:16'h7bef;
   p565=dut.video.graphics.wave_trace||dut.video.graphics.wave_grid ? blend(fg):16'd0;q[0]=expand(p565);
  end
 end

 initial begin


  force dut.video.layer_em.pixel=16'd0;force dut.video.frame_safe_output=1'b0;force dut.video.missing_tags=21'd0;
  repeat(10)@(negedge clk);rst=1;wait(dut.pixel_rst_n);wait(frames>=4);wait(dut.raw_fs);repeat(25)@(negedge dut.pixel_clk);
  ck(captured_total>=1536&&comparisons>30000,"multiple512-sample real PCM blocks and complete raster regions checked");
  ck(dut.video.graphics.spectrum_ready&&dut.video.graphics.spectrum_sequence>=2,"actual audio path publishes FFT spectra at frame boundaries");
  ck(panel_file!=0&&panel_pixels==288*124,"complete spectrum panel artifact contains every physical output pixel");
  if(panel_file!=0)begin $fclose(panel_file);panel_file=0;end
  ck(dut.video.USER_FEATURES==1&&dut.video.FLEX_SPECTRUM==1&&dut.video.VOLUME_COLUMNS==0&&dut.video.VOLUME_SETTING==0,"production replaces both old columns with real frequency spectrum");
  ck(dut.boot_seconds>10&&dut.boot_bcd_pixel!=0,"configuration counter delivered through actual acknowledged pixel mailbox");
  saved_time=dut.boot_seconds;rst=0;repeat(100)@(negedge clk);rst=1;wait(dut.sys_rst_n&&dut.pixel_rst_n);repeat(100)@(negedge clk);
  ck(dut.boot_seconds>=saved_time&&dut.boot_seconds!=0,"KEY1 cannot clear boot elapsed seconds");
  if(!errors)$display("[PASS] production audio samples and RGB spectrum endpoint across three frames;uptime mailbox and warm reset HD%0d",HD);
  done=1;
 end

function signed [4:0] v_cast_s5; input signed [4:0] value; begin begin v_cast_s5=value; end  end endfunction
function signed [5:0] v_cast_s6; input signed [5:0] value; begin begin v_cast_s6=value; end  end endfunction
endmodule
module tb_v3_feature_board_base198;
 wire done;wire[31:0]e,c;feature_board198 dut(done,e,c);
 initial begin wait(done);$display("[TB] tb_v3_feature_board_base198 done errors=%0d comparisons=%0d",e,c);$finish;end
 initial begin #120000000;$display("[FAIL] board feature watchdog errors=1");$finish;end
endmodule
module tb_v3_feature_board_hd198;
 wire done;wire[31:0]e,c;feature_board198 #(.HD(1)) dut(done,e,c);
 initial begin wait(done);$display("[TB] tb_v3_feature_board_hd198 done errors=%0d comparisons=%0d",e,c);$finish;end
 initial begin #120000000;$display("[FAIL] board feature watchdog errors=1");$finish;end
endmodule
