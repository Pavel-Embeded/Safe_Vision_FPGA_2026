`timescale 1ns/1ps
`include "safevision_defs.vh"
module tb_v3_geometry_live_miter;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,flex_mode=1,valid=0,sof=0,eof=0,out_ready=1,force_stall=0,checking=0;
 reg[7:0] data=0,bpp=24;reg[15:0] width=1,height=1;reg top_down=0;
 wire ready[0:1],rready[0:1],pv[0:1],rpv[0:1],done[0:1],rdone[0:1],bad[0:1],rbad[0:1];
 wire[15:0] pixel[0:1],rpixel[0:1];wire[9:0] x[0:1],y[0:1],rx[0:1],ry[0:1];
 wire isof[0:1],ieof[0:1],risof[0:1],rieof[0:1];wire[7:0] code[0:1],detail[0:1],rcode[0:1],rdetail[0:1];
 wire[3:0] state[0:1],rstate[0:1];wire[61:0] public_bus[0:1],reference_bus[0:1];
 genvar g;generate for(g=0;g<2;g=g+1)begin:pair
  wire reset_pair=rst_n&&(flex_mode==g);
  v3_bmp_normalizer #(.FLEX_PIXELS(g)) dut(.clk(clk),.rst_n(reset_pair),.din(data),.din_valid(valid),.din_ready(ready[g]),.din_sof(sof),.din_eof(eof),.width(width),.height(height),.top_down(top_down),.bpp(bpp),.pixel(pixel[g]),.pixel_valid(pv[g]),.pixel_ready(out_ready),.x(x[g]),.y(y[g]),.img_sof(isof[g]),.img_eof(ieof[g]),.done(done[g]),.error(bad[g]),.err_code(code[g]),.err_detail(detail[g]),.dbg_state(state[g]));
  v3_bmp_normalizer_frozen_live261028 #(.FLEX_PIXELS(g)) original(.clk(clk),.rst_n(reset_pair),.din(data),.din_valid(valid),.din_ready(rready[g]),.din_sof(sof),.din_eof(eof),.width(width),.height(height),.top_down(top_down),.bpp(bpp),.pixel(rpixel[g]),.pixel_valid(rpv[g]),.pixel_ready(out_ready),.x(rx[g]),.y(ry[g]),.img_sof(risof[g]),.img_eof(rieof[g]),.done(rdone[g]),.error(rbad[g]),.err_code(rcode[g]),.err_detail(rdetail[g]),.dbg_state(rstate[g]));
  assign public_bus[g]={ready[g],pixel[g],pv[g],x[g],y[g],isof[g],ieof[g],done[g],bad[g],code[g],detail[g],state[g]};
  assign reference_bus[g]={rready[g],rpixel[g],rpv[g],rx[g],ry[g],risof[g],rieof[g],rdone[g],rbad[g],rcode[g],rdetail[g],rstate[g]};
 end endgenerate
 integer errors=0,comparisons=0,cycles=0,pixels=0,sent=0,frame_w=1,frame_h=1,frame_bits=24,stride=4,total=4,case_id=0;
 integer full_frames=0,invalid_sizes=0,invalid_eofs=0,async_checks=0,stalled_cycles=0;
 integer since_reset=0,max_flex_without_reset=0,max_legacy_without_reset=0;
 reg saw_done=0,saw_error=0,was_stalled=0;reg[37:0] held_output;
 reg[31:0] random_state=32'h7ab40c35;
 task ck(input  ok,input [4095:0] message);begin
  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<16)$display("[FAIL] %s case=%0d mode=%0d sent=%0d state=%0d/%0d",message,case_id,flex_mode,sent,state[flex_mode],rstate[flex_mode]);end
   end endtask
 always@(negedge clk)begin
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  out_ready=!force_stall&&(random_state[3:0]!=0)&&(random_state[6:4]!=1);
 end
 always@(posedge clk)if(checking)begin
  cycles = cycles + 1;
  if(rst_n)begin
   if(was_stalled)begin
    stalled_cycles = stalled_cycles + 1;ck(pv[flex_mode]&&{pixel[flex_mode],x[flex_mode],y[flex_mode],isof[flex_mode],ieof[flex_mode]}===held_output,"output and tags hold through backpressure until the accepting edge");
   end
   was_stalled=pv[flex_mode]&&!out_ready;
   held_output={pixel[flex_mode],x[flex_mode],y[flex_mode],isof[flex_mode],ieof[flex_mode]};
   if(pv[flex_mode]&&out_ready)pixels = pixels + 1;
   if(done[flex_mode])begin saw_done=1;saw_error=bad[flex_mode];end
  end else was_stalled=0;
  #0.001;
  ck(public_bus[1]===reference_bus[1],"all62FLEX public bits agree on every cycle, including invalid output cycles");
  ck(public_bus[0]===reference_bus[0],"all62legacy public bits agree on every cycle");
 end
 function[7:0] payload(input integer pos);integer row,col,channel;begin
  row=pos/stride;col=pos%stride;channel=col%(frame_bits/8);
  if(pos>=total)payload=8'hd3;
  else if(col>=frame_w*(frame_bits/8))payload=8'had;
  else if(channel==3)payload=8'ha5;
  else payload=(case_id*31+(col/(frame_bits/8))*17+row*29+channel*47)&255;
   end endfunction
 task setup_case(input integer wi,he,bits,input  td);begin
  td = (td === 1'b1); @(negedge clk);valid=0;sof=0;eof=0;force_stall=0;
  frame_w=wi;frame_h=he;frame_bits=bits;width=wi;height=td ? -he:he;top_down=td;bpp=bits;
  stride=((wi*(bits/8)+3)/4)*4;total=stride*he;sent=0;pixels=0;saw_done=0;saw_error=0;case_id = case_id + 1;
   end endtask
 task drive_bytes(input integer count);reg pending,take;begin
  pending= ((0) === 1'b1);
  while(sent<count&&!saw_done)begin
   @(negedge clk);
   if(!pending)begin
    valid=random_state[10:8]!=3'b010;
    if(valid)begin pending= ((1) === 1'b1);data=payload(sent);sof=sent==0;eof=sent==count-1;end
   end
   @(posedge clk);take= ((valid&&ready[flex_mode]) === 1'b1);#0.002;
   if(take)begin sent = sent + 1;pending= ((0) === 1'b1);end
  end
  @(negedge clk);valid=0;sof=0;eof=0;
   end endtask
 task finish_case(input  want_error);begin
  want_error = (want_error === 1'b1); wait(saw_done);repeat(3)@(negedge clk);
  ck(saw_error===want_error,"completion error class matches supplied stream");
  ck(state[flex_mode]==0&&!pv[flex_mode],"completion returns to idle without a lingering pixel");
   end endtask
 task image(input integer wi,he,bits,input  td);begin
  td = (td === 1'b1); setup_case(wi,he,bits,td);drive_bytes(total);finish_case(0);
  ck(sent==total&&pixels==307200,"complete stream emits exactly one canonical frame");
  full_frames = full_frames + 1;since_reset = since_reset + 1;
  if(flex_mode&&since_reset>max_flex_without_reset)max_flex_without_reset=since_reset;
  if(!flex_mode&&since_reset>max_legacy_without_reset)max_legacy_without_reset=since_reset;
  $display("[PASS] public-cycle miter complete mode%0d %0dx%0d %0dbpp td%0d noresetframes%0d",flex_mode,wi,he,bits,td,since_reset);
   end endtask
 task invalid_size(input integer wi,he,input  td);begin
  td = (td === 1'b1); setup_case(wi,he,24,td);@(negedge clk);valid=1;sof=1;eof=0;data=8'h57;
  @(posedge clk);#0.002;@(negedge clk);valid=0;sof=0;
  finish_case(1);ck(code[flex_mode]==`ERR_MEDIA_INVALID&&detail[flex_mode]==`DET_BMP_SIZE,"invalid dimensions retain precise diagnostics");
  ck(pixels==0,"invalid dimensions emit no pixels");invalid_sizes = invalid_sizes + 1;
   end endtask
 task invalid_tail(input integer wi,he,bits,count,input  td);begin
  td = (td === 1'b1); setup_case(wi,he,bits,td);drive_bytes(count);finish_case(1);
  ck(code[flex_mode]==`ERR_MEDIA_INVALID&&detail[flex_mode]==`DET_BMP_TRUNC,"early/late EOF retain truncation diagnostics");invalid_eofs = invalid_eofs + 1;
   end endtask
 task asynchronous_reset;begin
  @(negedge clk);#2;rst_n=0;valid=0;sof=0;eof=0;was_stalled=0;since_reset=0;
  #0.001;
  ck(public_bus[1]===reference_bus[1]&&public_bus[0]===reference_bus[0],"asynchronous reset immediately agrees with the frozen parent");
  ck(pixel[flex_mode]===16'd0&&!pv[flex_mode]&&x[flex_mode]==0&&y[flex_mode]==479&&state[flex_mode]==0&&!bad[flex_mode]&&!done[flex_mode],"asynchronous reset restores all observable reset values before another clock");
  async_checks = async_checks + 1;#7;rst_n=1;force_stall=0;@(negedge clk);
   end endtask
 task abort_setup(input  second_edge);begin
  second_edge = (second_edge === 1'b1); setup_case(37,23,24,1);@(negedge clk);valid=1;sof=1;eof=0;data=8'h83;
  @(posedge clk);#0.002;ck(state[1]==1,"SOF enters the unchanged geometry state");
  if(second_edge)begin @(posedge clk);#0.002;ck(state[1]==14,"first setup edge enters the unchanged decision state");end
  asynchronous_reset();
   end endtask
 task abort_stalled_output;begin
  setup_case(1,1,24,1);force_stall=1;drive_bytes(total);
  wait(pv[1]);repeat(11)@(posedge clk);ck(!out_ready&&pv[1],"reset recovery is exercised during an actual held pixel");asynchronous_reset();
   end endtask
 initial begin
  repeat(3)@(negedge clk);checking=1;asynchronous_reset();
  image(3,2,24,0);image(2,3,32,1);image(17,13,24,1);image(1,1,32,0);image(16384,1,24,1);image(1,16384,32,0);
  invalid_size(0,1,0);invalid_size(1,0,1);invalid_size(16385,1,0);invalid_size(1,16385,0);invalid_size(1,16385,1);invalid_size(65535,1,0);invalid_size(1,32768,0);invalid_size(1,32768,1);
  invalid_tail(3,2,24,7,0);invalid_tail(2,1000,32,7992,1);invalid_tail(4,1,32,17,1);image(5,4,32,1);
  abort_setup(0);abort_setup(1);abort_stalled_output();image(3,5,24,0);
  @(negedge clk);rst_n=0;valid=0;sof=0;eof=0;flex_mode=0;asynchronous_reset();
  image(3,2,24,0);image(2,3,24,1);image(1,1,24,0);
  invalid_size(0,1,0);invalid_size(1,0,1);invalid_size(1921,1,0);invalid_size(1,1081,0);invalid_size(1,1081,1);invalid_size(65535,1,0);invalid_size(1,32768,0);invalid_size(1,32768,1);
  invalid_tail(3,2,24,7,0);invalid_tail(1,1,24,5,1);image(7,3,24,1);
  ck(full_frames==12&&invalid_sizes==16&&invalid_eofs==5,"all directed cases completed");
  ck(max_flex_without_reset>=7&&max_legacy_without_reset>=4,"sequential images retain private state across changing geometry without reset");
  ck(async_checks==5&&stalled_cycles>100000&&cycles>1000000,"reset timing and backpressure coverage are substantial");
  if(!errors)$display("[PASS] full parent model,62public bits in both modes, sequential frames, stalls, asynchronous recovery and invalid streams");
  $display("PASS tb_v3_geometry_live_miter errors=%0d comparisons=%0d cycles=%0d frames=%0d invalid_sizes=%0d invalid_eofs=%0d async_checks=%0d stalled_cycles=%0d",errors,comparisons,cycles,full_frames,invalid_sizes,invalid_eofs,async_checks,stalled_cycles);$finish;
 end
 initial begin #2000000000;errors = errors + 1;$display("[FAIL] public-cycle miter watchdog");$display("PASS tb_v3_geometry_live_miter errors=%0d comparisons=%0d",errors,comparisons);$finish;end
endmodule
