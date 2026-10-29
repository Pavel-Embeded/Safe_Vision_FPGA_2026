

`timescale 1ns/1ps
module tb_bmp_frame_sink_drain;
 reg mc=0,wc=0;always #4 mc=~mc;always #10 wc=~wc;
 reg rst=0,fa=0,valid=0,drained=0,busy=0;reg [31:0] word=0;
 wire ready,mready,fd,ok,req,sw,crc;wire [31:0] addr,data;
 wire [15:0] len,fc;wire [1:0] slot;wire [7:0] gen,ec,ed;wire [3:0] state;wire [18:0] px;
 bmp_frame_sink #(.REQUIRE_WRITE_DRAIN(1),.SWAP_TO_N(200),.WRITE_TO_N(200000)) dut(
 .clk(mc),.rst_n(rst),.wr_clk(wc),.px_word(word),.px_word_valid(valid),.px_word_ready(ready),
 .frame_active(fa),.top_down(1'b1),.slot(2'd1),.mem_ready(mready),.frame_done(fd),.last_frame_ok(ok),
 .wr_req(req),.wr_addr(addr),.wr_data(data),.wr_len(len),.wr_ready(1'b1),
 .swap_toggle(sw),.swap_slot(slot),.swap_generation(gen),.swap_crc_ok(crc),.swap_busy(busy),
 .state_o(state),.err_code(ec),.err_detail(ed),.frame_cnt(fc),.px_written(px),.write_drained(drained));
 integer errors=0,checks=0,writes=0;
 always @(posedge mc)if(req)writes=writes+1;
 task check(input  condition,input [4095:0] name);
 begin begin condition = (condition === 1'b1); checks=checks+1;if(condition)$display("[PASS] %s",name);
 else begin errors=errors+1;$display("[FAIL] %s",name);end end  end endtask
 task send_frame;
 integer k;
 begin begin
   wait(mready);@(negedge wc);fa=1;repeat(10)@(negedge wc);
   for(k=0;k<153600;k=k+1)begin
     @(negedge wc);word={16'h1234,16'h5678};valid=1;
     @(posedge wc);while(!ready)@(posedge wc);
   end
   @(negedge wc);valid=0;
 end  end endtask
 reg saved_sw,saved_fd;
 initial begin
   repeat(10)@(negedge mc);rst=1;
   send_frame;wait(state==4);saved_sw=sw;
   repeat(100)@(negedge mc);
   check(sw==saved_sw&&state==4,"frame publication held while accepted writes are not physically drained");
   check(writes==153600&&px==307200,"all words traversed actual async FIFO and writer before drain wait");
   @(negedge mc);drained=1;wait(sw!=saved_sw);
   check(crc&&slot==1,"drained frame published with valid CRC and slot metadata");
   @(negedge mc);busy=1;repeat(20)@(negedge mc);saved_fd=fd;busy=0;
   wait(fd!=saved_fd);check(ok,"acknowledged frame returns successful completion");
   @(negedge wc);fa=0;repeat(30)@(negedge wc);


   wait(mready);saved_sw=sw;saved_fd=fd;
   @(negedge wc);fa=1;wait(state==1);
   check(!ok,"new frame cannot inherit the previous frame's success level");
   @(negedge mc);force dut.br_err=1'b1;force dut.br_ec=8'h03;
   @(negedge mc);release dut.br_err;release dut.br_ec;
   wait(fd!=saved_fd);
   check(!ok&&ec==8'h03,"write error after a successful frame returns failure");
   check(fc==1&&sw==saved_sw,"failed write neither publishes nor counts a frame");
   @(negedge wc);fa=0;repeat(30)@(negedge wc);
   send_frame;saved_fd=fd;wait(fd!=saved_fd);
   check(!ok&&ec==8'hf1,"missing swap acknowledgement returns failure F1, never successful completion");
   check(fc==1,"failed swap does not increase successful frame count");
   $display("SINK DRAIN checks=%0d errors=%0d",checks,errors);
   if(errors)begin $display("[FAIL] sink drain regression failed"); $finish; end 
   $display("[PASS] SINK DRAIN PASS");$finish;
 end
 initial begin #150000000;begin $display("[FAIL] sink drain watchdog state=%0d",state); $finish; end end
endmodule
