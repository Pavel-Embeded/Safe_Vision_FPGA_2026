`timescale 1ns/1ps
module handbook_coords_case #(parameter HD=0)(output reg done=0,output integer errors=0,comparisons=0);
 reg clk=0,rst=0,de=0,fit=0;always #5 clk=~clk;reg[11:0]x=0,y=0;reg[1:0]mode=0;
 wire valid;wire[9:0]sx,sy;wire[7:0]fx,fy;
 scaler_coords #(.HD(HD),.HANDBOOK_PROFILE(1)) dut(clk,rst,de,x,y,fit,mode,valid,sx,sy,fx,fy);
 integer m,xx,yy,w,h,ox,oy,ew,eh,ex,ey,efx,efy,i;
 reg ev[0:1];reg[9:0]esx[0:1],esy[0:1];reg[7:0]efxx[0:1],efyy[0:1];
 task point(input integer px,py);begin
  @(negedge clk);x=px;y=py;de=1;
  ev[1]=ev[0];esx[1]=esx[0];esy[1]=esy[0];efxx[1]=efxx[0];efyy[1]=efyy[0];
  ev[0]=px>=ox&&py>=oy&&px<ox+ew&&py<oy+eh;
  ex=px-ox;ey=py-oy;efx=0;efy=0;
  if(m==1&&HD)begin efx=((ex*2)%3)*256/3;efy=((ey*2)%3)*256/3;ex=ex*2/3;ey=ey*2/3;end
  else if(m>=2)begin ex=ex*(m==2?2:4);ey=ey*(m==2?2:4);end
  esx[0]=ex;esy[0]=ey;efxx[0]=efx;efyy[0]=efy;
  @(posedge clk);#1;comparisons++;
  if(valid!==ev[1]||(valid&&{sx,sy,fx,fy}!=={esx[1],esy[1],efxx[1],efyy[1]}))begin
   errors++;if(errors<8)$display("[FAIL] coordinates HD=%0d mode=%0d xy=%0d,%0d got=%d,%d expected=%d,%d",HD,m,px,py,sx,sy,esx[1],esy[1]);end
 end endtask
 initial begin
  ev[0]=0;ev[1]=0;for(i=0;i<2;i++)begin esx[i]=0;esy[i]=0;efxx[i]=0;efyy[i]=0;end
  repeat(3)@(negedge clk);rst=1;w=HD?1280:640;h=HD?720:480;
  for(m=0;m<4;m++)begin mode=m;ew=m==0?640:m==1?w:m==2?320:160;eh=m==0?480:m==1?h:m==2?240:120;
   if(m==1&&HD)ew=960;ox=(w-ew)/2;oy=(h-eh)/2;
   for(yy=0;yy<h;yy++)for(xx=0;xx<w;xx++)point(xx,yy);
   point(w,h);point(w,h);
  end
  if(errors==0)$display("[PASS] all pixels, black borders and exact two-cycle ratios HD=%0d",HD);done=1;
 end
endmodule
module tb_v3_handbook_coords;
 wire d0,d1;wire integer e0,e1,c0,c1;
 handbook_coords_case #(.HD(0)) b(d0,e0,c0);handbook_coords_case #(.HD(1)) h(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[TB] tb_v3_handbook_coords done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
endmodule
