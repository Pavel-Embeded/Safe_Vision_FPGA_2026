`timescale 1ns/1ps


module tb_v3_directory_fault550;
 reg clk=0,rst_n=0,run=0;always #10 clk=~clk;
 reg crc_bad=1,token_bad=0;wire cs,sclk,mosi,miso;wire[5:0] cmd;wire[31:0] arg;
 wire dead=token_bad&&cmd==17&&arg==20;
 wire[3:0] state,stage,cv;wire[7:0] ec,ed;wire mounted,pxv;integer errors=0,comparisons=0,guard=0,mode=0,i;
 sd_spi_fault_card550 #(.VOL_BASE(16),.VOL_SECTORS(8192)) card(.sclk(sclk),.cs_n(cs),.mosi(mosi),.miso(miso),.i_dead(dead),.i_crc_bad(crc_bad),.o_cmd(cmd),.o_arg(arg));
 sd_bmp_player #(.FLEX_FILES(1),.RESIDENT_CACHE(1),.SHARED_SERVICE(1),.GUARDED_CS(1),.CLK_HZ(50000000),.CLK_DIV_INIT(249),.CLK_DIV_FAST(0)) d(
 .clk(clk),.rst_n(rst_n),.cs_guard_rst_n(rst_n),.run(run),.btn_next(1'b0),.btn_auto(1'b0),.restart(1'b0),
 .sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),.sd_miso(miso),.px_word_valid(pxv),.px_word_ready(1'b1),.mem_ready(1'b1),.frame_done(1'b0),.last_frame_ok(1'b1),
 .state_o(state),.fail_stage(stage),.err_code(ec),.err_detail(ed),.cache_valid(cv),.card_usable(mounted),
 .external_core_cmd(445'd0),.ext_rd_en(1'b0),.ext_rd_addr(32'd0),.ext_rd_len(16'd1),.ext_data_ready(1'b1),.media_descriptor_ready(1'b1));
 always @(posedge clk)if(rst_n&&pxv)begin errors = errors + 1;if(errors<5)$display("[FAIL] partial directory produced a pixel");end
 initial begin
  $readmemh("resident_card.mem",card.vol);for(i=0;i<8192;i=i+1)card.vol_used[i]=1;
  card.sector[450]=8'h0c;card.sector[454]=16;card.sector[455]=0;card.sector[456]=0;card.sector[457]=0;
  card.sector[458]=0;card.sector[459]=32;card.sector[460]=0;card.sector[461]=0;card.sector[510]=8'h55;card.sector[511]=8'haa;
  for(mode=0;mode<2;mode=mode+1)begin
   rst_n=0;run=0;crc_bad=mode==0;token_bad=mode==1;repeat(5)@(negedge clk);rst_n=1;run=1;guard=0;
   while(state!=10&&guard<2000000)begin @(negedge clk);guard = guard + 1;end
   comparisons = comparisons + 1;
   if(state!=10||stage!=4||ec!=2||ed!=(mode==0 ? 8'h22:8'h23)||cv!=0||mounted)begin
    errors = errors + 1;$display("[FAIL] directory fault mode%0d state%0d stage%0d code%h/%h cache%h mounted%b",mode,state,stage,ec,ed,cv,mounted);
   end
  end
  if(!errors)$display("[PASS] real SPI directory CRC and token timeout after candidates fail closed with no partial index/cache/pixels");
  $display("[TB] tb_v3_directory_fault550 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin repeat(5000000)@(negedge clk);$display("[FAIL] directory fault watchdog errors=1");$finish;end
endmodule
