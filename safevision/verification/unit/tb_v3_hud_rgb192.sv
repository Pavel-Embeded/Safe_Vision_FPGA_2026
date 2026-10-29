`timescale 1ns/1ps
module hud_rgb_case192 #(parameter HD=0)(output reg done=0,output integer errors=0,comparisons=0);
 reg clk=0,rst=0;always #10 clk=~clk;
 reg[15:0] fg=0,bg=0;reg on=0,checking=0;
 safevision_v3_top #(.HD(HD)) dut(.clk(clk),.rst_n(rst),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 function[15:0] blend(input[15:0]f,b,input bit en);integer r,g,bl,a;begin
 a=en?224:0;r=(f[15:11]*a+b[15:11]*(255-a)+127)/255;
 g=(f[10:5]*a+b[10:5]*(255-a)+127)/255;bl=(f[4:0]*a+b[4:0]*(255-a)+127)/255;
 blend={5'(r),6'(g),5'(bl)};end endfunction
 function[23:0]expand(input[15:0]p);begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
 function[15:0]colour(input integer c);begin case(c)0:colour=16'hffff;1:colour=16'h07e0;2:colour=16'h7bef;3:colour=16'h05bf;4:colour=16'hffe0;default:colour=16'hf800;endcase end endfunction
 function[15:0]background(input integer c);begin case(c)0:background=0;1:background=16'hffff;2:background=16'h7bef;3:background=16'hf800;4:background=16'h07e0;5:background=16'h001f;6:background=16'ha55a;default:background=16'h5aa5;endcase end endfunction
 reg[15:0]q[0:2];reg[2:0]vq=0;reg[23:0]expected_rgb;integer i,c,b,m;
 always@(posedge dut.pixel_clk)begin
  if(dut.pixel_rst_n!==1'b1)begin for(i=0;i<3;i++)q[i]=0;vq=0;expected_rgb=0;end
  else begin
   expected_rgb=dut.video.tags[19][26]?expand(q[2]):24'd0;
   for(i=2;i>0;i--)q[i]=q[i-1];
   q[0]=blend(dut.video.hud_pixels[12],dut.video.o2,dut.video.hud_alphas[12][7]);
   vq={vq[1:0],dut.video.ov2};
  end
  #0.001;
  if(checking)begin comparisons+=3;
   if(dut.video.o3!==q[2]||dut.video.ov3!==vq[2]||dut.video.rgb!==expected_rgb)begin
    errors++;if(errors<9)$display("[FAIL] production RGB HD=%0d fg=%h HUD=%h/%h RGB=%h/%h",HD,dut.video.hud_pixels[12],dut.video.o3,q[2],dut.video.rgb,expected_rgb);
   end
  end
 end
 initial begin


  force dut.video.graphics.hud_rgb565=fg;force dut.video.graphics.hud_alpha=on?8'd224:8'd0;
  force dut.video.layer_em.pixel=bg;force dut.video.frame_safe_output=1'b0;force dut.video.missing_tags=21'd0;
  repeat(10)@(negedge clk);rst=1;wait(dut.pixel_rst_n&&dut.sys_rst_n);repeat(40)@(negedge dut.pixel_clk);checking=1;
  for(c=0;c<6;c++)for(b=0;b<8;b++)for(m=0;m<2;m++)begin
   @(negedge dut.pixel_clk);fg=colour(c);bg=background(b);on=m;repeat(8)@(negedge dut.pixel_clk);
   if(c==3&&b==4&&m==1)begin #1;rst=0;repeat(8)@(negedge clk);rst=1;wait(dut.pixel_rst_n);end
  end
  repeat(40)@(negedge dut.pixel_clk);done=1;
 end
endmodule
`ifdef HD_HUD_RGB_SOURCE
module tb_v3_hud_rgb_hd192;
 wire done;wire integer errors,comparisons;hud_rgb_case192 #(.HD(1))d(done,errors,comparisons);
 initial begin wait(done);#2;if(!errors)$display("[PASS] HD production selector,full seven-bit channels,HUD three-edge pipeline and final RGB888;actual clocks/DE/reset,all six produced colours and eight backgrounds");$display("[TB] tb_v3_hud_rgb_hd192 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #2000000;$display("[FAIL] HD HUD RGB watchdog errors=1");$finish;end
endmodule
`else
module tb_v3_hud_rgb_base192;
 wire done;wire integer errors,comparisons;hud_rgb_case192 #(.HD(0))d(done,errors,comparisons);
 initial begin wait(done);#2;if(!errors)$display("[PASS] BASE production selector,HUD three-edge pipeline and final RGB888;actual clocks/DE/reset,all six produced colours and eight backgrounds");$display("[TB] tb_v3_hud_rgb_base192 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #2000000;$display("[FAIL] BASE HUD RGB watchdog errors=1");$finish;end
endmodule
`endif
