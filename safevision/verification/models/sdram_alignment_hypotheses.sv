
`timescale 1ns/1ps
module sdram(input Clk,Clk_sft,Rst,output Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,
 input App_wr_en,input[20:0]App_wr_addr,input[3:0]App_wr_dm,input[31:0]App_wr_din,
 input App_rd_en,input[20:0]App_rd_addr,output Sdr_rd_en,output[31:0]Sdr_rd_dout);
 reg[31:0] mem[0:2097151];
 integer valid_lag=0;
 reg[20:0]err_address=21'h1fffff;reg[31:0]err_mask=0;
 reg[20:0]address[0:5];reg[5:0]valid=0;reg[31:0]data=0;
 integer k,b;reg[7:0]init_count=0;
 assign Sdr_init_done=init_count==255;
 assign Sdr_init_ref_vld=0;assign Sdr_busy=0;
 assign Sdr_rd_en=valid[4+valid_lag];assign Sdr_rd_dout=data;
 always @(posedge Clk)begin
  if(Rst)begin valid<=0;data<=0;init_count<=0;end
  else begin
   if(init_count!=255)init_count<=init_count+1'b1;
   valid<={valid[4:0],App_rd_en};address[0]<=App_rd_addr;
   for(k=1;k<6;k=k+1)address[k]<=address[k-1];
   if(valid[3])data<=mem[address[3]]^((address[3]==err_address)?err_mask:0);
   if(App_wr_en)for(b=0;b<4;b=b+1)if(!App_wr_dm[b])mem[App_wr_addr][8*b+:8]<=App_wr_din[8*b+:8];
  end
 end
endmodule
