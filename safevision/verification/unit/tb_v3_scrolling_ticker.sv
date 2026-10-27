`timescale 1ns/1ps
module ticker_raster_case #(parameter WIDTH=640,HEIGHT=480,STEP=2,FULL_RASTER=1,
 parameter NAME="tb_v3_ticker_base");
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,fs=0,de=0;reg[11:0] x=0,y=0;
 wire panel,dot,edge_bit;wire[11:0] position;wire[15:0] frames,loops;
 v3_scrolling_ticker #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FRAMES_PER_PIXEL(STEP),
  .BITMAP_FILE("v3_ticker16.mem")) dut(.clk(clk),.rst_n(rst_n),.frame_start(fs),
  .x(x),.y(y),.de(de),.panel_pixel(panel),.text_pixel(dot),.edge_pixel(edge_bit),
  .position(position),.frames(frames),.loops(loops));
 reg reference_pixels[0:8191];reg qp[0:20],qt[0:20],qe[0:20];
 integer model_position=0,model_divider=0,model_frames=0,model_loops=0;
 integer errors=0,comparisons=0,steps=0,i,xx,yy,ph,frame,source_column;
 reg want_panel,want_text,want_edge;
 localparam PERIOD=(WIDTH-128)+21*16;
 task ck(input bit okay,input string message);begin
  comparisons++;
  if(!okay)begin errors++;if(errors<15)$display("[FAIL] %s phase=%0d x=%0d y=%0d t=%t",message,model_position,x,y,$time);end
 end endtask
 task tick(input integer px,py,input bit active,start_frame);begin
  @(negedge clk);x=px;y=py;de=active;fs=start_frame;
  // Signed screen-space construction is independent of the RTL's unsigned
  // sum/subtract and packed character/row ROM addressing.
  want_panel=active&&px>=120&&px<WIDTH-8&&py>=HEIGHT-24&&py<HEIGHT-4;
  want_edge=want_panel&&py==HEIGHT-24;
  source_column=(px-120)-((WIDTH-128)-model_position);
  want_text=0;
  if(want_panel&&py>=HEIGHT-22&&py<HEIGHT-6&&source_column>=0&&source_column<336)
   want_text=reference_pixels[(py-(HEIGHT-22))*512+source_column];
  @(posedge clk);#1;
  for(i=20;i>0;i=i-1)begin qp[i]=qp[i-1];qt[i]=qt[i-1];qe[i]=qe[i-1];end
  qp[0]=want_panel;qt[0]=want_text;qe[0]=want_edge;
  if(start_frame)begin
   model_frames=(model_frames+1)&65535;
   model_divider++;
   if(model_divider==STEP)begin
    model_divider=0;model_position++;
    if(model_position==PERIOD)begin model_position=0;model_loops=(model_loops+1)&65535;end
   end
  end
  ck(panel===qp[20],"panel clips and retains the21-clock raster tag");
  ck(dot===qt[20],"glyph pixels match independent row-major font reference");
  ck(edge_bit===qe[20],"top rule aligns with the same output pixel");
  ck(position===model_position,"position changes at the specified frame cadence");
  ck(frames===model_frames,"frame counter records every frame exactly once");
  ck(loops===model_loops,"loop count changes only after the full message leaves");
  steps++;
 end endtask
 task reset_async;begin
  @(negedge clk);rst_n=0;fs=0;de=0;#2;
  ck(panel===0&&dot===0&&edge_bit===0,"asynchronous pixel reset immediately blanks all ticker outputs");
  model_position=0;model_divider=0;model_frames=0;model_loops=0;
  for(i=0;i<21;i=i+1)begin qp[i]=0;qt[i]=0;qe[i]=0;end
  repeat(2)@(negedge clk);rst_n=1;
 end endtask
 initial begin
  $readmemb("pixels.mem",reference_pixels);
  for(i=0;i<21;i=i+1)begin qp[i]=0;qt[i]=0;qe[i]=0;end
  reset_async;
  if(FULL_RASTER)begin
   for(frame=0;frame<2;frame=frame+1)
    for(yy=0;yy<525;yy=yy+1)
     for(xx=0;xx<800;xx=xx+1)
      tick(xx,yy,xx<640&&yy<480,xx==0&&yy==480);
   $display("[PASS] two complete production BASE rasters and blanking");
  end
  // Every phase of the entry, full traversal, exit and blank interval.
  // BASE also checks the complete line, including the reserved UP region.
  for(ph=0;ph<PERIOD;ph=ph+1)begin
   for(yy=HEIGHT-25;yy<HEIGHT-2;yy=yy+1)
    for(xx=(FULL_RASTER?0:117);xx<(FULL_RASTER?WIDTH:WIDTH-5);xx=xx+1)
     tick(xx,yy,(xx%7)!=0,0);
   repeat(STEP)tick(0,HEIGHT,0,1);
  end
  $display("[PASS] all scroll positions, character columns, rows, borders and disabled DE samples");
  // Counter boundary injection changes only verification state, followed by
  // ordinary public frame pulses. It is not a long-running hardware claim.
  @(negedge clk);fs=0;dut.frames=16'hffff;model_frames=65535;
  tick(0,HEIGHT,0,1);
  ck(frames==0,"16-bit frame counter wraps without losing a frame");
  reset_async;
  repeat(32)tick(200,HEIGHT-20,1,0);
  ck(position==0&&frames==0,"no pixel or line activity advances the scroll phase");
  $display("[PASS] reset, held raster, frame and loop counter behavior");
  $display("PASS %s errors=%0d comparisons=%0d steps=%0d",NAME,errors,comparisons,steps);
  $finish;
 end
 initial begin repeat(30)#100000000;$display("[FAIL] ticker bounded watchdog errors=1");$finish;end
endmodule

module tb_v3_ticker_base;
 ticker_raster_case #(.NAME("tb_v3_ticker_base")) check_case();
endmodule
module tb_v3_ticker_clip;
 ticker_raster_case #(.WIDTH(160),.HEIGHT(80),.STEP(3),.FULL_RASTER(0),.NAME("tb_v3_ticker_clip")) check_case();
endmodule
