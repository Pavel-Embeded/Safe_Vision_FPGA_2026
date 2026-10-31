`timescale 1ns/1ps
module hdmi_bridge_case #(parameter integer HD=0)(output reg done);
 initial begin done = 0; end

 localparam W=HD ? 1280:640,H=HD ? 720:480,HT=HD ? 1650:800,VT=HD ? 750:525;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [11:0] x=0,y=0;wire de=x<W&&y<H;
 wire [23:0] rgb={x[7:0],y[7:0],v_cast_u8(x+y)};
 wire valid,user,last,resync,fault;wire [23:0] data;wire [31:0] drops;wire [4:0] level;
 reg ready=1;integer cycle=0,stall=0;reg injected=0;
 hdmi_video_bridge #(.HD(HD)) dut(.clk(clk),.rst_n(rst),.de(de),.x(x),.y(y),.rgb(rgb),
  .axis_valid(valid),.axis_user(user),.axis_last(last),.axis_data(data),.axis_ready(ready),
  .resync(resync),.overflow_sticky(fault),.dropped_frames(drops),.queue_level(level));
 always @(posedge clk)if(rst&&!done)begin
  if(x==HT-1)begin x<=0;if(y==VT-1)y<=0;else y<=y+1;end else x<=x+1;
 end
 reg [25:0] golden[0:1023];integer put=0,get=0,compared=0,frames=0,line=0;
 reg wait_frame=1,held=0;reg [25:0] held_value;
 always @(negedge clk)if(rst&&!done)begin
  cycle=cycle+1;
  if(!injected&&y==1&&x==200)begin stall=32;injected=1;end

  if(stall>0)begin ready=0;stall=stall-1;end else ready=(cycle%601>=3);
 end
 always @(posedge clk)if(rst&&!done)begin
  if(held&&!resync&&{user,last,data}!==held_value)begin $display("[FAIL] AXIS payload changed while stalled"); $finish; end
  held=valid&&!ready;held_value={user,last,data};
  if(valid&&ready)begin
   if(get>=put||{user,last,data}!==golden[get%1024])begin $display("[FAIL] HDMI packet ordering HD=%0d packet=%0d",HD,get); $finish; end
   if(user)line=0;
   if(last)begin
    if(line==H-1)frames=frames+1;line=line+1;
   end
   get=get+1;compared=compared+1;
  end
  if(de&&(!wait_frame||(x==0&&y==0)))begin
   golden[put%1024]={(x==0&&y==0),(x==W-1),rgb};put=put+1;wait_frame=0;
  end
  #0.1;
  if(resync)begin put=0;get=0;wait_frame=1;held=0;line=0;end
  if(level!==put-get)begin $display("[FAIL] HDMI queue accounting"); $finish; end
  if(frames>=2)begin
   if(!fault||drops!=1||compared<2*W*H)begin $display("[FAIL] overflow/recovery coverage"); $finish; end
   $display("PASS HDMI bridge HD=%0d compared=%0d complete_recovered_frames=%0d drops=%0d stable stalls/SOF/TLAST",HD,compared,frames,drops);done=1;
  end
 end
 initial begin #33;rst=1;end

function [7:0] v_cast_u8; input [7:0] value; begin  v_cast_u8=value;   end endfunction
endmodule
module tb_hdmi_video_bridge;
 wire [1:0] done;hdmi_bridge_case #(.HD(0)) a(done[0]);hdmi_bridge_case #(.HD(1)) b(done[1]);
 initial begin wait(&done);$display("PASS tb_hdmi_video_bridge");$finish;end
 initial begin #60000000;begin $display("[FAIL] HDMI bridge watchdog"); $finish; end end
endmodule
