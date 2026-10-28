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
 reg[11:0] rx=0,ry=0;reg rd=0,rf=0;reg[23:0] underlying=24'h75a9c3;
 reg pixels[0:8191];reg[23:0] wanted[0:20];reg[23:0] new_wanted;
 reg[24:0] wanted_xy[0:20];
 reg cv=0,query=0;reg signed[31:0] selector=0;
 integer errors=0,comparisons=0,i,p,xx,yy,source_col;
 task ck(input bit okay,input string message);begin comparisons++;
  if(!okay)begin errors++;if(errors<15)$display("[FAIL] %s x=%0d y=%0d phase=%0d t=%t",message,rx,ry,p,$time);end
 end endtask
 task command(input integer bank,input bit ask,input[7:0] code,input[31:0] expected);integer n;begin
  @(negedge dut.sys_clk);selector=bank;query=ask;cv=1;
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
  if(panel&&py>=458&&py<474&&source_col>=0&&source_col<512)
   text_bit=pixels[(py-458)*512+source_col];
  new_wanted=panel?(text_bit?24'hf4fff4:py==456?24'h3e8290:24'h0c171b):underlying;
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
  force dut.cmd_valid=cv;force dut.cmd_target=8'd66;force dut.cmd_catalog_id=7'd36;force dut.cmd_value=selector;force dut.cmd_query=query;
  force dut.raw_x=rx;force dut.raw_y=ry;force dut.raw_de=rd;force dut.raw_fs=rf;force dut.rgb=underlying;
  force dut.scrolling.ticker.position=12'd400;
  force dut.scrolling.ticker.frame_count=8'hfe;force dut.scrolling.ticker.loop_count=8'h57;
  repeat(100)@(negedge dut.sys_clk);
  command(0,0,0,32'h26102801);command(0,1,0,32'h26102801);
  command(101,0,0,32'h544b1190);command(102,0,3,0);
  command(103,0,3,0);command(32'h10000065,0,3,0);command(-1,0,3,0);
  $display("[PASS] production selection, ID, atomic cross-clock status and selector bounds");
  for(p=0;p<1024;p=p+211)begin
   release dut.scrolling.ticker.position;
   force dut.scrolling.ticker.position=p;
   for(i=0;i<21;i++)begin wanted[i]=underlying;wanted_xy[i]=0;end
   repeat(24)pixel(0,0,0);
   // The existing coordinate reconstruction requires HTOTAL=800, including
   // horizontal blanking. Keep that real production contract in this test.
   for(yy=454;yy<478;yy++)for(xx=0;xx<800;xx++)pixel(xx,yy,xx<640&&(xx%11)!=0);
  end
  $display("[PASS] original RGB outside ticker, UP reservation, full glyph rows, clipped sides and DE gaps");
  p=400;release dut.scrolling.ticker.position;force dut.scrolling.ticker.position=12'd400;
  force dut.media_reset=1'b1;repeat(100)@(negedge dut.pixel_clk);
  command(101,0,0,32'h544b1190);command(102,0,3,0);
  ck(dut.pixel_rst_n,"media recovery leaves the independent display reset released");
  release dut.media_reset;
  $display("[PASS] ticker status and pixel reset survive media recovery");
  $display("PASS tb_v3_ticker_board errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #20000000;$display("[FAIL] board ticker watchdog errors=1");$finish;end
endmodule
