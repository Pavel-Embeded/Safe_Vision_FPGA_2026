// Reproduces the board's first-block CRC: zeros expected, all FF returned.
// Actual adapter; functional controller model includes read DQM suppression.
`timescale 1ns/1ps
module tb_sdram_read_dqm #(parameter integer RD_LAT=11);
 `include "crc32_word.vh"
 reg clk=0;always #12.5 clk=~clk;
 reg rst_n=0,req=0,wr=0;reg [31:0] addr=0,data=0;reg [3:0] strb=15;
 wire ready,idone,rv,aw,ar,init,refv,busy,sv,idle,fault;
 wire [31:0] dout,wd,sd;wire [20:0] wa,ra;wire [3:0] dm;
 sdram_app_adapter #(.FAST_READ(1),.PREFETCH_READ(1)) dut(
 .clk(clk),.rst_n(rst_n),.req(req),.wr(wr),.addr(addr),.wdata(data),.wstrb(strb),
 .ready(ready),.init_done(idone),.rdata(dout),.rdata_valid(rv),
 .App_wr_en(aw),.App_rd_en(ar),.App_wr_addr(wa),.App_rd_addr(ra),
 .App_wr_din(wd),.App_wr_dm(dm),.Sdr_init_done(init),.Sdr_init_ref_vld(refv),
 .Sdr_busy(busy),.Sdr_rd_en(sv),.Sdr_rd_dout(sd),.write_idle(idle),.protocol_fault(fault));
 sdram #(.RD_LAT(RD_LAT)) memory(.Clk(clk),.Clk_sft(clk),.Rst(!rst_n),
 .App_wr_en(aw),.App_rd_en(ar),.App_wr_addr(wa),.App_rd_addr(ra),
 .App_wr_din(wd),.App_wr_dm(dm),.Sdr_init_done(init),.Sdr_init_ref_vld(refv),
 .Sdr_busy(busy),.Sdr_rd_en(sv),.Sdr_rd_dout(sd));
 integer i,n,received=0,masked_padding=0,bad_words=0;
 reg [31:0] crc=32'hffffffff;
 always @(posedge clk)if(aw&&dm==15)masked_padding=masked_padding+1;
 always @(negedge clk)if(rv)begin
   crc=crc32_word(crc,dout);received=received+1;
   if(dout!==0)bad_words=bad_words+1;
 end
 initial begin
   // Preserve a nonzero neighbour to detect accidental dummy-beat overwrite.
   memory.mem[21'h28040]=32'h12345678;
   repeat(5)@(negedge clk);rst_n=1;wait(idone);
   for(i=0;i<64;i=i+1)begin
     @(negedge clk);req=1;wr=1;addr=32'h28000+i;data=0;strb=15;
     n=0;@(posedge clk);while(!ready&&n<10000)begin n=n+1;@(posedge clk);end
     if(n==10000)$fatal(1,"write handshake timeout");
     @(negedge clk);req=0;repeat(200)@(negedge clk);
   end
   wait(idle);repeat(32)@(negedge clk);
   req=1;wr=0;
   for(i=0;i<64;i=i+1)begin
     addr=32'h28000+i;n=0;
     @(posedge clk);while(!ready&&n<10000)begin n=n+1;@(posedge clk);end
     if(n==10000)$fatal(1,"read handshake timeout");
     @(negedge clk);
   end
   req=0;repeat(40)@(negedge clk);
   $display("DQM REPRO LAT=%0d WORDS=%0d PAD=%0d EXPECTED=0D968558 ACTUAL=%08x DM=%x",RD_LAT,received,masked_padding,~crc,dm);
   if(received!=64||masked_padding!=64||memory.mem[21'h28040]!==32'h12345678||fault)
     $fatal(1,"SDRAM_READ_DQM_PROTOCOL");
   if(bad_words||~crc!=32'h0d968558)$fatal(1,"SDRAM_READ_MASK_STUCK_F");
   $display("PASS tb_sdram_read_dqm: 64 slow writes / untouched neighbour / exact first-block CRC");$finish;
 end
 initial begin #2000000;$fatal(1,"DQM regression watchdog");end
endmodule
