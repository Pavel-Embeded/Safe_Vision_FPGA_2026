`timescale 1ns/1ps


module v3_pressure_app_model #(parameter integer REFRESH_CYCLES=312)(
 input wire clk,rst,wr_en,rd_en,input wire[20:0] wr_addr,rd_addr,
 input wire[31:0] wr_data,input wire[3:0] wr_dm,
 output wire initialized,ref_valid,busy,output reg valid=0,output reg[31:0] data=0);
 reg[31:0] memory[0:2097151];
 integer cycle=0,init_count=0,last_cmd=-1000,head=0,tail=0,depth=0;
 integer due[0:63];reg[20:0] addresses[0:63];
 reg[3:0] masks[0:8];reg last_w=0,last_r=0;
 reg[20:0] previous;integer wn=0,rn=0;
 reg[20:0] wa[0:15];reg[31:0] wd[0:15];reg[3:0] dm[0:15];
 integer read_bursts=0,write_bursts=0,refresh_events=0,protocol_errors=0,i,j,b;
 assign initialized=init_count==100;
 assign ref_valid=initialized&&cycle%REFRESH_CYCLES<8;
 assign busy=wr_en||rd_en||depth!=0||ref_valid;
 task violation(input string message);begin
  protocol_errors=protocol_errors+1;$fatal(1,"App contract %s cycle=%0d",message,cycle);
 end endtask
 always @(posedge clk)begin
  cycle=cycle+1;valid<=0;
  if(rst)begin
   init_count=0;head=0;tail=0;depth=0;wn=0;rn=0;last_w=0;last_r=0;last_cmd=-1000;
   for(i=0;i<9;i=i+1)masks[i]=15;
  end else begin
   if(init_count<100)init_count=init_count+1;
   if(initialized&&cycle%REFRESH_CYCLES==0)refresh_events=refresh_events+1;
   if(depth!=0&&due[head]<=cycle&&cycle%REFRESH_CYCLES>=8)begin
    data<=memory[addresses[head]];
    for(b=0;b<4;b=b+1)if(masks[8][b])data[b*8+:8]<=8'hff;
    valid<=1;head=(head+1)%64;depth=depth-1;
   end
   for(i=8;i>0;i=i-1)masks[i]=masks[i-1];masks[0]=wr_dm;
   if(wr_en&&rd_en)violation("simultaneous write/read");
   if((wr_en&&!last_w)||(rd_en&&!last_r))
    if(cycle-last_cmd<17)violation("less than 16 quiet clocks");
   if(wr_en)begin
    if(wn>=16)violation("write length exceeds 16");
    if(wn>0&&wr_addr!==wa[wn-1]+1)violation("nonconsecutive write");
    wa[wn]=wr_addr;wd[wn]=wr_data;dm[wn]=wr_dm;wn=wn+1;
   end
   if(last_w&&!wr_en)begin
    if(wn<2)violation("unmasked single physical write");
    for(j=0;j<wn;j=j+1)for(b=0;b<4;b=b+1)
     if(!dm[j][b])memory[wa[j]][b*8+:8]=wd[j][b*8+:8];
    wn=0;write_bursts=write_bursts+1;
   end
   if(rd_en)begin
    if(last_r&&rd_addr!==previous+1)violation("nonconsecutive read");
    if(depth>=64)violation("response queue overflow");
    previous=rd_addr;rn=rn+1;addresses[tail]=rd_addr;due[tail]=cycle+4;
    tail=(tail+1)%64;depth=depth+1;
   end
   if(last_r&&!rd_en)begin
    if(rn!=16)violation("read length differs from 16");
    rn=0;read_bursts=read_bursts+1;
   end
   if(wr_en||rd_en)last_cmd=cycle;last_w=wr_en;last_r=rd_en;
  end
 end
endmodule
