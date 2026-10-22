`timescale 1ns/1ps
module feature_board198 #(parameter HD=0)(output reg done=0,output integer errors=0,comparisons=0);
 reg clk=0,rst=0;always #10 clk=~clk;
 safevision_v3_top #(.HD(HD)) dut(.clk(clk),.rst_n(rst),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 defparam dut.uptime.CLK_HZ=50000;
 localparam W=HD?1280:640,H=HD?720:480;
 integer capture[0:255],displayed[0:255],count=0,captured_total=0,shown=0,i,j,idx,aa,bb,ya,yb;
 reg published=0,trace,grid;reg[15:0] fg,p565;reg[23:0] q[0:20];reg[20:0] vq=0;integer frames=0,saved_time;
 function[15:0]blend(input[15:0]f);integer r,g,b;begin
 r=(f[15:11]*224+127)/255;g=(f[10:5]*224+127)/255;b=(f[4:0]*224+127)/255;blend={5'(r),6'(g),5'(b)};end endfunction
 function[23:0]expand(input[15:0]p);begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
 task ck(input bit ok,input string m);begin comparisons++;if(!ok)begin errors++;if(errors<8)$display("[FAIL] HD%0d %s",HD,m);end end endtask
 always@(posedge dut.pixel_clk)begin
  if(!dut.pixel_rst_n)begin count=0;published=0;vq=0;for(i=0;i<21;i++)q[i]=0;end
  else begin
   if(dut.raw_fs)begin
    frames++;
    if(count==128)begin for(i=0;i<128;i++)displayed[i]=capture[i];count=0;published=1;shown++;end
   end else if(dut.pcm_valid&&count<128)begin capture[count]=$signed(dut.pcm_left[23:16]);count++;captured_total++;end
   for(i=20;i>0;i--)begin q[i]=q[i-1];vq[i]=vq[i-1];end
   vq[0]=published&&dut.raw_de&&dut.raw_x>=W-272&&dut.raw_x<W-16&&dut.raw_y>=H-130&&dut.raw_y<H-62;
   q[0]=0;
   if(vq[0])begin
    idx=(dut.raw_x-(W-272))/2;aa=displayed[idx==0?0:idx-1]>>>2;bb=displayed[idx]>>>2;
    ya=H-96-aa;yb=H-96-bb;
    trace=dut.raw_y>=(ya<yb?ya:yb)&&dut.raw_y<=(ya>yb?ya:yb);
    grid=dut.raw_y==H-96||dut.raw_y==H-130||dut.raw_y==H-63||dut.raw_x==W-272||dut.raw_x==W-17;
    fg=trace?16'h05bf:16'h7bef;p565=trace||grid?blend(fg):16'd0;q[0]=expand(p565);
   end
   #0.001;
   if(vq[20])ck(dut.video.rgb===q[20],"actual alarm ROM -> priority -> volume -> packet FIFO -> waveform RAM -> HUD -> finalRGB");
  end
 end
 initial begin
  // Isolate the HUD against a known previous-layer background. Actual audio,
  // PCM CDC, scope renderer, scan tags, palette and finalRGB remain unforced.
  force dut.video.layer_em.pixel=16'd0;force dut.video.frame_safe_output=1'b0;force dut.video.missing_tags=21'd0;
  repeat(10)@(negedge clk);rst=1;wait(dut.pixel_rst_n);wait(shown>=3);wait(dut.raw_fs);repeat(25)@(negedge dut.pixel_clk);
  ck(captured_total>=384&&comparisons>30000,"multiple complete real-PCM captures and physical scan regions checked");
  ck(dut.video.USER_FEATURES==1&&dut.video.VOLUME_COLUMNS==0&&dut.video.VOLUME_SETTING==0,"production replaces both old columns with real waveform");
  ck(dut.boot_seconds>10&&dut.boot_bcd_pixel!=0,"configuration counter delivered through actual acknowledged pixel mailbox");
  saved_time=dut.boot_seconds;rst=0;repeat(100)@(negedge clk);rst=1;wait(dut.sys_rst_n&&dut.pixel_rst_n);repeat(100)@(negedge clk);
  ck(dut.boot_seconds>=saved_time&&dut.boot_seconds!=0,"KEY1 cannot clear boot elapsed seconds");
  if(!errors)$display("[PASS] production audio samples and RGB waveform endpoint across three frames;uptime mailbox and warm reset HD%0d",HD);
  done=1;
 end
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
