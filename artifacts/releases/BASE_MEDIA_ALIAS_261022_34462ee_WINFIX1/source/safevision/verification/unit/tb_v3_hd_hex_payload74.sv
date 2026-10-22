`timescale 1ns/1ps
module hex_payload_case74 #(parameter HD=0,HB=0)(output reg done=0,output integer errors=0,comparisons=0);
 localparam H=HD?720:480,CW=HB?99:96;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[11:0]x=0,y=0;reg[98:0]cfg=0;reg[31:0]under=0,rng=32'h74abcd;reg[3:0]cache=0;
 wire[15:0]a0,a1,a2,a3,b0,b1,b2,b3;wire[7:0]aa0,aa1,aa2,ba0,ba1,ba2;
 v3_status_layers #(.HD(HD),.HANDBOOK_PROFILE(HB),.RASTER_PREDECODE(0),.PIXEL_HZ(74),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE(HB?"v3_handbook_status_text.mem":"v3_status_text.mem")) dut(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(1'b1),.frame_start(1'b0),.cfg_data(cfg[CW-1:0]),.cache_valid(cache),.underflows(under),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),.osd_rgb565(a0),.emergency_rgb565(a1),.hud_rgb565(a2),.safe_rgb565(a3),.osd_alpha(aa0),.emergency_alpha(aa1),.hud_alpha(aa2));
 v3_hd_status_reference #(.HD(HD),.HANDBOOK_PROFILE(HB),.PIXEL_HZ(74),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE(HB?"v3_handbook_status_text.mem":"v3_status_text.mem")) golden(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(1'b1),.frame_start(1'b0),.cfg_data(cfg[CW-1:0]),.cache_valid(cache),.underflows(under),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),.osd_rgb565(b0),.emergency_rgb565(b1),.hud_rgb565(b2),.safe_rgb565(b3),.osd_alpha(ba0),.emergency_alpha(ba1),.hud_alpha(ba2));
 always @(posedge clk)begin #1;comparisons++;
  if(rst&&({a0,a1,a2,a3,aa0,aa1,aa2}!=={b0,b1,b2,b3,ba0,ba1,ba2}||(golden.normal_v1&&dut.normal_effective!==golden.normal_effective)))begin
   errors++;if(errors<8)$display("[FAIL] HEX/public raster HD=%0d HB=%0d x=%0d y=%0d cfg=%h got=%h want=%h",HD,HB,x,y,cfg,dut.normal_effective,golden.normal_effective);
  end
 end
 integer f,i,b,k;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<256;f++)for(b=0;b<3;b++)for(i=0;i<64;i++)for(k=0;k<4;k++)begin
   @(negedge clk);rng=rng*1664525+1013904223;under=rng;cache=rng[3:0];cfg={rng,rng^32'h13579bdf,rng^32'habcdef12,3'b0};cfg[47:40]=f;
   x=8+i*8+k*2;y=b==0?29+k:b==1?45+k:H-59+k;
  end
  repeat(8)@(negedge clk);done=1;
 end
endmodule
module tb_v3_hd_hex_payload74;
 wire d0,d1,d2,d3;wire integer e0,e1,e2,e3,c0,c1,c2,c3;
 hex_payload_case74 #(.HD(0),.HB(0)) a(d0,e0,c0);
 hex_payload_case74 #(.HD(0),.HB(1)) b(d1,e1,c1);
 hex_payload_case74 #(.HD(1),.HB(0)) c(d2,e2,c2);
 hex_payload_case74 #(.HD(1),.HB(1)) d(d3,e3,c3);
 initial begin wait(d0&&d1&&d2&&d3);#2;
  if(e0+e1+e2+e3==0)$display("[PASS] all256 fault encodings including zero,all64 character indices,cache/underflow/address nibble windows,BASE/HD and both profiles;original public output latency");
  $display("PASS tb_v3_hd_hex_payload74 errors=%0d comparisons=%0d",e0+e1+e2+e3,c0+c1+c2+c3);$finish;
 end
 initial begin #3000000;$display("[FAIL] HEX watchdog");$display("PASS tb_v3_hd_hex_payload74 errors=1 comparisons=0");$finish;end
endmodule
