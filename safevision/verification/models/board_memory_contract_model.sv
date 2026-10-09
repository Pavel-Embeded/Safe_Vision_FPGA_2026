// Application protocol model, NOT the encrypted vendor controller or SDRAM AC.
// Uses the project's measured M-11 minimum write shape. Tests byte masks,
// delayed burst commit, consecutive addresses, command spacing and turnarounds.
// Compile this INSTEAD OF vendor_ip_stub.sv; the same module names are required.
`timescale 1ns/1ps
module sv_system_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);
 reg sys=0,mem=0;always #5 sys=~sys;always #4 mem=~mem;
 assign clk0_out=sys;assign clk1_out=mem;assign clk2_out=~mem;assign extlock=1;
endmodule
module sdram #(parameter integer RD_LAT=4)(
 input wire Clk,Clk_sft,Rst,output wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,
 input wire App_wr_en,input wire [20:0] App_wr_addr,input wire [3:0] App_wr_dm,
 input wire [31:0] App_wr_din,input wire App_rd_en,input wire [20:0] App_rd_addr,
 output reg Sdr_rd_en=0,output reg [31:0] Sdr_rd_dout=0);
 reg [31:0] mem[0:2097151];
 integer init_count=0,cycle=0,last_cmd=-1000,n=0,read_n=0;
 integer write_bursts=0,read_bursts=0,stored_words=0,protocol_errors=0;
 reg last_w=0,last_r=0;reg [20:0] previous_r;
 reg [20:0] wa[0:15];reg [31:0] wd[0:15];reg [3:0] dm[0:15];
 reg [RD_LAT-1:0] rv=0;reg [20:0] ra[0:RD_LAT-1];
 integer i,j,b;
 assign Sdr_init_done=(init_count==100);
 assign Sdr_init_ref_vld=0;assign Sdr_busy=App_wr_en||App_rd_en||(|rv);
 task violation(input string message);
 begin protocol_errors=protocol_errors+1;$fatal(1,"SDRAM contract: %s cycle=%0d",message,cycle);end endtask
 always @(posedge Clk)begin
   cycle=cycle+1;
   if(Rst)begin
     init_count=0;rv=0;Sdr_rd_en<=0;last_w=0;last_r=0;n=0;read_n=0;last_cmd=-1000;
   end else begin
     if(init_count<100)init_count=init_count+1;
     Sdr_rd_en<=rv[RD_LAT-1];
     if(rv[RD_LAT-1])Sdr_rd_dout<=mem[ra[RD_LAT-1]];
     for(i=RD_LAT-1;i>0;i=i-1)ra[i]=ra[i-1];
     ra[0]=App_rd_addr;rv={rv[RD_LAT-2:0],App_rd_en};
     if(App_wr_en&&App_rd_en)violation("simultaneous read and write");
     if((App_wr_en&&!last_w)||(App_rd_en&&!last_r))
       if(cycle-last_cmd<17)violation("fewer than 16 quiet clocks between bursts");
     if(App_wr_en)begin
       if(n>=16)violation("oversize physical write burst");
       if(n>0&&App_wr_addr!==wa[n-1]+1)violation("nonconsecutive write address");
       wa[n]=App_wr_addr;wd[n]=App_wr_din;dm[n]=App_wr_dm;n=n+1;
     end
     if(last_w&&!App_wr_en)begin
       if(n<2)violation("one-beat write burst");
       for(j=0;j<n;j=j+1)begin
         if(dm[j]!=15)stored_words=stored_words+1;
         for(b=0;b<4;b=b+1)if(!dm[j][b])mem[wa[j]][8*b+:8]=wd[j][8*b+:8];
       end
       write_bursts=write_bursts+1;n=0;
     end
     if(App_rd_en)begin
       if(last_r&&App_rd_addr!==previous_r+1)violation("nonconsecutive read address");
       previous_r=App_rd_addr;read_n=read_n+1;
     end
     if(last_r&&!App_rd_en)begin
       if(read_n!=16)violation("read burst is not 16 commands");
       read_bursts=read_bursts+1;read_n=0;
     end
     if(App_wr_en||App_rd_en)last_cmd=cycle;
     last_w=App_wr_en;last_r=App_rd_en;
   end
 end
endmodule

module sv_board_memory_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);
 reg sys=0;always #5 sys=~sys;
 reg mem=0;always #12.5 mem=~mem;
 assign clk0_out=sys;assign clk1_out=mem;assign #10 clk2_out=mem;assign extlock=1;
endmodule
