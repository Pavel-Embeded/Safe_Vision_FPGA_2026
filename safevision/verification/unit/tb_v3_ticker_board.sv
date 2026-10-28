`timescale 1ns/1ps
module tb_v3_ticker_board;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 wire txd;wire[3:0]led;wire scl;tri sda;
 safevision_v3_top dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),
 .uart_rxd(1'b1),.uart_txd(txd),.led(led),.sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),
 .HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P(),.HDMI_CLK_P(),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_status_text.mem";
 defparam dut.scrolling.ticker.BITMAP_FILE="v3_ticker16.mem";
 defparam dut.video.graphics.spectrum.analyzer.SHARED_INIT_FILE="v3_spectrum_ticker.mem";
 reg[11:0] rx=0,ry=0;reg rd=0,rf=0;reg[23:0] underlying=24'h75a9c3;
 reg pixels[0:4095];reg[23:0] wanted[0:20];reg[23:0] new_wanted;
 reg[24:0] wanted_xy[0:20];
 reg cv=0,query=0;reg signed[31:0] selector=0;reg[6:0] catalog=36;
 reg[31:0] q0=0,q1=0,q2=0,q3=0,q4=0,packed_expected;integer basis;
 integer errors=0,comparisons=0,i,p,xx,yy,source_col;
 task ck(input bit okay,input string message);begin comparisons++;
  if(!okay)begin errors++;if(errors<15)$display("[FAIL] %s x=%0d y=%0d phase=%0d t=%t",message,rx,ry,p,$time);end
 end endtask
 task frame_pulse;begin
  @(negedge dut.pixel_clk);rx=0;ry=480;rd=0;rf=1;
  @(negedge dut.pixel_clk);rf=0;
 end endtask
 task command(input integer bank,input bit ask,input[7:0] code,input[31:0] expected);integer n;begin
  @(negedge dut.sys_clk);catalog=36;selector=bank;query=ask;cv=1;
  @(negedge dut.sys_clk);cv=0;n=0;
  while(!dut.b_reply&&n<200)begin @(negedge dut.sys_clk);n++;end
  ck(dut.b_reply&&dut.b_reply_code===code,"production diagnostic completion/code");
  if(code==0)ck(dut.b_reply_value===expected,"production diagnostic exact payload");
  repeat(10)@(negedge dut.sys_clk);ck(!dut.b_reply,"production reply has no duplicate");
 end endtask
 task pixel(input integer px,py,input bit active);reg panel,text_bit;begin
  @(negedge dut.pixel_clk);rx=px;ry=py;rd=active;rf=0;
  panel=active&&px>=120&&px<632&&py>=456&&py<476;
  source_col=px-(632-p);text_bit=0;
  if(panel&&py>=458&&py<474&&source_col>=0&&source_col<256)
   text_bit=pixels[(py-458)*256+source_col];
  new_wanted=panel?(text_bit?24'hffffff:py==456?24'h008080:24'h000000):underlying;
  @(posedge dut.pixel_clk);#0.001;
  for(i=20;i>0;i--)begin wanted[i]=wanted[i-1];wanted_xy[i]=wanted_xy[i-1];end
  wanted[0]=new_wanted;wanted_xy[0]={active,12'(px),12'(py)};
  ck(dut.out_de===wanted_xy[20][24],"original DE retains its raster latency");
  if(wanted_xy[20][24])ck({dut.out_x,dut.out_y}===wanted_xy[20][23:0],"reconstructed production coordinates match a legal full-width raster");
  ck(dut.rendered_rgb===wanted[20],"production RGB mux preserves image outside strip and aligns every glyph");
 end endtask
 initial begin
  $readmemb("pixels.mem",pixels);
  repeat(10)@(negedge clk);rst_n=1;wait(dut.sys_rst_n&&dut.pixel_rst_n);
  ck(dut.TICKER_ENABLE==1,"production source list enables ticker");
  force dut.cmd_valid=cv;force dut.cmd_target=8'd66;force dut.cmd_catalog_id=catalog;force dut.cmd_value=selector;force dut.cmd_query=query;
  force dut.raw_x=rx;force dut.raw_y=ry;force dut.raw_de=rd;force dut.raw_fs=rf;force dut.rgb=underlying;
  force dut.scrolling.ticker.position=12'd400;
  repeat(100)@(negedge dut.sys_clk);
  command(0,0,0,32'h26102801);command(0,1,0,32'h26102801);
  command(101,0,0,32'h544b1190);command(102,0,3,0);
  command(103,0,3,0);command(32'h10000065,0,3,0);command(-1,0,3,0);
  $display("[PASS] production selection, ID, atomic cross-clock status and selector bounds");
  force dut.b_query_next0=q0;force dut.b_query_next1=q1;force dut.b_query_next2=q2;
  force dut.b_query_next3=q3;force dut.b_query_next4=q4;
  for(basis=0;basis<256;basis++)begin
   @(negedge dut.sys_clk);catalog=dut.B_QUERY_STATUS;selector=0;query=1;
   q0=0;q1=0;q2=0;q3=0;q4=0;
   if(basis<160)begin case(basis/32)
    0:q0=32'd1<<(basis%32);1:q1=32'd1<<(basis%32);
    2:q2=32'd1<<(basis%32);3:q3=32'd1<<(basis%32);
    4:q4=32'd1<<(basis%32);endcase
   end else begin q0=$urandom;q1=$urandom;q2=$urandom;q3=$urandom;q4=$urandom;end
   packed_expected=q0|q1|q2|q3|q4;cv=1;
   @(negedge dut.sys_clk);cv=0;q0=~q0;q1=~q1;q2=~q2;q3=~q3;q4=~q4;
   ck(dut.b_reply&&dut.b_reply_code==0,"packed query replies on the original acceptance edge");
   ck(dut.b_reply_value===packed_expected,"all five full32-bit live groups are captured before subsequent changes");
   repeat(10)@(negedge dut.sys_clk);ck(!dut.b_reply,"packed query has exactly one reply");
  end
  release dut.b_query_next0;release dut.b_query_next1;release dut.b_query_next2;
  release dut.b_query_next3;release dut.b_query_next4;catalog=36;query=0;
  $display("[PASS] packed query basis vectors, random live buses, exact capture edge and single replies");
  for(p=0;p<768;p=p+211)begin
   release dut.scrolling.ticker.position;
   force dut.scrolling.ticker.position=p;
   for(i=0;i<21;i++)begin wanted[i]=underlying;wanted_xy[i]=0;end
   repeat(24)pixel(0,0,0);
   // The existing coordinate reconstruction requires HTOTAL=800, including
   // horizontal blanking. Keep that real production contract in this test.
   for(yy=454;yy<478;yy++)for(xx=0;xx<800;xx++)pixel(xx,yy,xx<640&&(xx%11)!=0);
  end
  $display("[PASS] original RGB outside ticker, UP reservation, full glyph rows, clipped sides and DE gaps");
  release dut.scrolling.ticker.position;
  ck(dut.scrolling.ticker.position==0,"unforced hardware scroll state starts at zero");
  repeat(10)frame_pulse;
  repeat(100)@(negedge dut.sys_clk);command(101,0,0,32'h544b1005);
  force dut.media_reset=1'b1;
  repeat(20)frame_pulse;
  repeat(100)@(negedge dut.sys_clk);command(101,0,0,32'h544b100f);command(102,0,3,0);
  ck(dut.scrolling.ticker.position==15,"actual scroll state advances through media reset");
  ck(dut.pixel_rst_n,"media recovery leaves the independent display reset released");
  release dut.media_reset;
  $display("[PASS] ticker status and pixel reset survive media recovery");
  $display("PASS tb_v3_ticker_board errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #20000000;$display("[FAIL] board ticker watchdog errors=1");$finish;end
endmodule
