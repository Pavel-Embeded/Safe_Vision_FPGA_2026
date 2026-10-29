`timescale 1ns/1ps
module tb_v3_video_constant224;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg enabled=0,valid=0;reg[1:0] foreground=0;reg[15:0] back=0;
 wire[15:0] emergency,hud;wire ev,hv;
 v3_constant224_blend #(.EMERGENCY(1)) a(clk,rst,valid,enabled,foreground,back,emergency,ev);
 v3_constant224_blend b(clk,rst,valid,enabled,foreground,back,hud,hv);
 function[15:0] reference(input[15:0] f,b,input  on);
  integer r,g,bl,alpha;begin begin on = (on === 1'b1); alpha=on ? 224:0;
   r=(f[15:11]*alpha+b[15:11]*(255-alpha)+127)/255;
   g=(f[10:5]*alpha+b[10:5]*(255-alpha)+127)/255;
   bl=(f[4:0]*alpha+b[4:0]*(255-alpha)+127)/255;
   reference={v_cast_s5(r),v_cast_s6(g),v_cast_s5(bl)};
  end
  end endfunction
 reg[15:0] expected_em[0:2],expected_hud[0:2];reg[2:0] expected_valid=0;
 integer errors=0,comparisons=0,k,bg,color,mask;
 wire[15:0] front=foreground==0 ? 16'hffff:foreground==1 ? 16'h07e0:16'h7bef;
 always @(posedge clk)begin
  if(!rst)begin for(k=0;k<3;k=k+1)begin expected_em[k]=0;expected_hud[k]=0;end expected_valid=0;end
  else begin
   for(k=2;k>0;k=k-1)begin expected_em[k]=expected_em[k-1];expected_hud[k]=expected_hud[k-1];end
   expected_em[0]=reference(16'hf800,back,enabled);expected_hud[0]=reference(front,back,enabled);
   expected_valid={expected_valid[1:0],valid};
   #1;
   if(emergency!==expected_em[2]||hud!==expected_hud[2]||ev!==expected_valid[2]||hv!==expected_valid[2])begin
    if(errors<8)$display("[FAIL] constant224 bg=%h color=%0d enabled=%b em=%h/%h hud=%h/%h valid=%b/%b",back,foreground,enabled,emergency,expected_em[2],hud,expected_hud[2],hv,expected_valid[2]);
    errors=errors+1;
   end
   comparisons=comparisons+4;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(color=0;color<4;color=color+1)for(mask=0;mask<2;mask=mask+1)for(bg=0;bg<65536;bg=bg+1)begin
   @(negedge clk);foreground=color;enabled=mask;back=bg;valid=(bg%7)!=2;
   if(color==2&&mask==0&&bg==32768)begin
    rst=0;repeat(3)@(negedge clk);rst=1;
   end
  end
  repeat(4)@(negedge clk);
  if(!errors)$display("[PASS] every RGB565 background, all fixed foregrounds, alpha0/224, invalid bubbles, three-clock latency and reset");
  $display("[TB] tb_v3_video_constant224 done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #20000000;$display("[FAIL] constant224 timeout errors=1");$finish;end

function signed [4:0] v_cast_s5; input signed [4:0] value; begin begin v_cast_s5=value; end  end endfunction
function signed [5:0] v_cast_s6; input signed [5:0] value; begin begin v_cast_s6=value; end  end endfunction
endmodule
