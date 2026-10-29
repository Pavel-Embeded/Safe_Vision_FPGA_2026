`timescale 1ns/1ps
module v3_frame_safe_test #(parameter integer HD=0);
 localparam HT=HD ? 1650:800,VT=HD ? 750:525,HA=HD ? 1280:640,VA=HD ? 720:480;
 localparam integer PIX_HZ=HD ? 74166667:25185185,PERIOD=HT*VT;
 reg clk=0,rst=0,req=0,s1=0,s2=0;always #5 clk=~clk;
 integer xx=0,yy=0,cycle=0;wire rawblank=yy>=VA;
 reg[26:0]tags[0:20];wire outblank=tags[19][11:0]>=VA;wire rawsafe,safe;
 reg output_safe=1;integer errors=0,comparisons=0,i,j,trial,start_tick,lat,maxlat=0,normal_frames=0,safe_frames=0;
 reg frame_value=1,seen_first=0;reg[31:0]rng=32'h26101704;
 v3_frame_safe_select d(clk,rst,rawblank,outblank,s2,rawsafe,safe);
 always@(posedge clk)begin
  if(!rst)begin xx<=0;yy<=0;cycle<=0;s1<=0;s2<=0;output_safe<=1;for(j=0;j<21;j = j + 1)tags[j]<=0;end
  else begin
   cycle<=cycle+1;s1<=req;s2<=s1;output_safe<=safe;
   tags[0]<={(xx<HA&&yy<VA),2'd0,v_cast_s12(xx),v_cast_s12(yy)};for(j=1;j<21;j = j + 1)tags[j]<=tags[j-1];
   if(xx==HT-1)begin xx<=0;yy<=yy==VT-1 ? 0:yy+1;end else xx<=xx+1;
  end
  #0.001;
  if(rst&&tags[20][26])begin
   comparisons = comparisons + 1;
   if(tags[20][23:0]==0)begin frame_value=output_safe;seen_first=1;if(output_safe)safe_frames = safe_frames + 1;else normal_frames = normal_frames + 1;end
   else if(seen_first&&output_safe!==frame_value)begin errors = errors + 1;if(errors<12)$display("[FAIL] partial normal/SAFE frame at x=%0d y=%0d",tags[20][23:12],tags[20][11:0]);end
  end
 end
 task wait_normal;
  begin begin req=0;wait(!rawsafe&&!safe);wait(tags[20][26]&&!output_safe&&tags[20][23:0]==0);end
  end endtask
 initial begin repeat(4)@(negedge clk);rst=1;
  for(trial=0;trial<100;trial = trial + 1)begin
   wait_normal();rng=rng*1664525+1013904223;
   case(trial%10)
    0:i=0;1:i=1;2:i=HA-1;3:i=VA*HT-2;4:i=VA*HT;5:i=PERIOD-2;6:i=PERIOD-25;default:i=rng%PERIOD;
   endcase
   repeat(i)@(negedge clk);req=1;start_tick=cycle;
   wait(tags[20][26]&&output_safe);lat=cycle-start_tick;
   comparisons = comparisons + 1;if(lat>maxlat)maxlat=lat;
   if(lat*1000.0/PIX_HZ>=16.7)begin errors = errors + 1;$display("[FAIL] confirmed-event to first SAFE visible pixel latency=%fms",lat*1000.0/PIX_HZ);end
   wait(tags[20][26]&&output_safe&&tags[20][23:0]==0);repeat(HT*VA)@(negedge clk);
  end
  if(safe_frames<100||normal_frames<100)begin errors = errors + 1;$display("[FAIL] insufficient complete active frames");end
  if(errors==0)$display("[PASS]100 phase-varied normal/SAFE switches, entire active frames, independent raw/output blanking, max%fms",maxlat*1000.0/PIX_HZ);
  if(HD)$display("[TB] tb_v3_frame_safe_hd done errors=%0d comparisons=%0d max_ticks=%0d",errors,comparisons,maxlat);
  else $display("[TB] tb_v3_frame_safe_base done errors=%0d comparisons=%0d max_ticks=%0d",errors,comparisons,maxlat);
  $finish;
 end

function signed [11:0] v_cast_s12; input signed [11:0] value; begin begin v_cast_s12=value; end  end endfunction
endmodule
module tb_v3_frame_safe_base;v3_frame_safe_test #(.HD(0)) t();endmodule
module tb_v3_frame_safe_hd;v3_frame_safe_test #(.HD(1)) t();endmodule
