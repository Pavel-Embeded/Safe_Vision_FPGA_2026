`timescale 1ns/1ps
module hdstatus_case233 #(parameter HD=0)(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 localparam W=HD ? 1280:640,H=HD ? 720:480;
 localparam HT=1650,VT=750;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[11:0]x=0,y=0;reg de=0,fs=0;reg[98:0]cfg=0;reg[31:0]up=0,uf=0;
 reg[3:0]cache=0;reg[1:0]slot=0;reg[7:0]gen=0;reg busy=0,safe=0,pv=0;reg[23:0]pcm=0;
 wire[87:0]a,b;


 always @(posedge clk or negedge rst)
  if(!rst)begin x<=0;y<=0;end
  else if(x==HT-1)begin x<=0;y<=y==VT-1 ? 0:y+1'b1;end
  else x<=x+1'b1;


 v3_status_layers #(.HD(HD),.RASTER_PREDECODE(1),.USER_FEATURES(1),.HANDBOOK_PROFILE(1),.PIXEL_HZ(1000),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) dut(
 .pixel_clk(clk),.pixel_rst_n(rst),.uptime_bcd(up),.wave_pcm_valid(pv),.wave_pcm_left(pcm),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg),.cache_valid(cache),.underflows(uf),.active_slot(slot),.generation(gen),.busy(busy),.safety_active(safe),.osd_rgb565(a[87:72]),.emergency_rgb565(a[71:56]),.hud_rgb565(a[55:40]),.safe_rgb565(a[39:24]),.osd_alpha(a[23:16]),.emergency_alpha(a[15:8]),.hud_alpha(a[7:0]));
 v3_status_layers226_hd_reference #(.HD(HD),.RASTER_PREDECODE(1),.USER_FEATURES(1),.HANDBOOK_PROFILE(1),.PIXEL_HZ(1000),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) oracle(
 .pixel_clk(clk),.pixel_rst_n(rst),.uptime_bcd(up),.wave_pcm_valid(pv),.wave_pcm_left(pcm),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg),.cache_valid(cache),.underflows(uf),.active_slot(slot),.generation(gen),.busy(busy),.safety_active(safe),.osd_rgb565(b[87:72]),.emergency_rgb565(b[71:56]),.hud_rgb565(b[55:40]),.safe_rgb565(b[39:24]),.osd_alpha(b[23:16]),.emergency_alpha(b[15:8]),.hud_alpha(b[7:0]));
 reg[31:0]r=32'h901a7235;integer px,py,frame,n=0;
 function[31:0] rnd(input[31:0] v);reg[31:0]z;begin  z=v^(v<<13);z=z^(z>>17);rnd=z^(z<<5);  end endfunction
 always@(posedge clk)begin #1;if(rst)begin comparisons = comparisons + 1;
  if(a!==b)begin errors = errors + 1;if(errors<15)$display("[FAIL] status descriptor HD=%0d x=%0d y=%0d a=%h b=%h cfg=%h",HD,x,y,a,b,cfg);end
 end end
 task stimulus;begin
  n = n + 1;r=rnd(r);pv=(n%31==0);pcm={r[15:0],8'd0};


  if(n%7==0)begin cfg={r,rnd(r),rnd(r^32'h1234),r[2:0]};up=rnd(r);uf=rnd(r^32'habcd);cache=r[7:4];slot=r[1:0];gen=r[15:8];busy=r[20];safe=r[21];end
   end endtask
 initial begin
  #100;@(negedge clk);rst=1;
  repeat(HT*VT*2)begin @(negedge clk);de=x<W&&y<H;fs=x==0&&y==H;stimulus();end
  @(negedge clk);rst=0;repeat(8)@(negedge clk);rst=1;
  repeat(HT*VT)begin @(negedge clk);de=x<W&&y<H;fs=x==0&&y==H;stimulus();end
  @(negedge clk);de=0;pv=0;repeat(8)@(negedge clk);
  if(!errors)$display("[PASS] actual HD override vs frozen226, all88 public RGB/alpha bits,3 complete nominal1650x750 rasters, live config and reset");
  done=1;
 end

endmodule
module tb_v3_hd_status_miter233;
 wire done;wire signed [31:0] errors,comparisons;
 hdstatus_case233 #(.HD(1)) x(done,errors,comparisons);
 initial begin wait(done);$display("[TB] tb_v3_hd_status_miter233 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #60000000;$display("[FAIL] HD status watchdog");$display("[TB] tb_v3_hd_status_miter233 done errors=1 comparisons=0");$finish;end
endmodule
