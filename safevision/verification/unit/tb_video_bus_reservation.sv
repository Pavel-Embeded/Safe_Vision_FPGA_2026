`timescale 1ns/1ps
module tb_video_bus_reservation;
 reg clk=0;always #12.5 clk=~clk;
 reg rst_n=0,rr=0,wr=0;reg [15:0] level=65535;
 wire ra,wa,rb,wb,mreq,mwr,rv;
 wire [31:0] addr;reg [2:0] responses=0;
 integer writes=0,reads=0,i;
 memory_arbiter #(.HIGH_WATER(3600),.CRITICAL_WATER(3000)) dut(
   .clk(clk),.rst_n(rst_n),.video_fifo_level(level),
   .rd_req(rr),.rd_addr(32'h000a0000),.rd_len(16'd64),.rd_ack(ra),.rd_busy(rb),
   .rd_data(),.rd_data_valid(rv),.wr_req(wr),.wr_addr(32'd0),.wr_data(32'h12345678),
   .wr_len(16'd1),.wr_ack(wa),.wr_busy(wb),.sd_req(1'b0),.sd_wr(1'b0),.sd_addr(32'd0),
   .sd_wdata(32'd0),.sd_len(16'd1),.sd_ack(),.sd_busy(),.sd_rdata(),.sd_rdata_valid(),
   .mem_req(mreq),.mem_wr(mwr),.mem_addr(addr),.mem_wdata(),.mem_wstrb(),
   .mem_ready(1'b1),.mem_rdata(32'habcd5678),.mem_rdata_valid(responses[2]),
   .wr_starve_cnt(),.rd_starve_cnt());
 always @(posedge clk)begin
   if(!rst_n)responses<=0;else responses<={responses[1:0],mreq&&!mwr};
   if(rst_n&&mreq)begin
     if(mwr)writes=writes+1;
     else begin if(addr!==32'h000a0000+reads*4)$fatal(1,"read ordering changed");reads=reads+1;end
   end
 end
 initial begin
   repeat(5)@(negedge clk);rst_n=1;wr=1;
   wait(wa);@(negedge clk);wr=0;wait(!wb);repeat(4)@(negedge clk);
   if(writes!=1)$fatal(1,"idle scan must allow startup image write");
   level=2000;wr=1;
   // Writer becomes urgent while the DMA prepares its next checked block.
   // Request gaps must not start an uninterruptible physical write tail.
   for(i=0;i<100;i=i+1)begin @(negedge clk);if(wa||wb||mreq)$fatal(1,"write stole low-water request gap");end
   rr=1;wait(ra);@(negedge clk);rr=0;wait(!rb);repeat(4)@(negedge clk);
   if(reads!=64||writes!=1)$fatal(1,"reserved video burst not completed exactly");
   level=65535;wait(wa);@(negedge clk);wr=0;wait(!wb);repeat(4)@(negedge clk);
   if(writes!=2)$fatal(1,"DMA idle must release writer reservation");
   $display("[PASS] VIDEO RESERVATION: startup write, 100-cycle urgent-writer request gap fenced, complete 64-word read, idle writer recovery");$finish;
 end
 initial begin #20000;$fatal(1,"reservation watchdog");end
endmodule
