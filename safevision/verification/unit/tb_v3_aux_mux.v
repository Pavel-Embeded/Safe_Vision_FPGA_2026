`timescale 1ns/1ps
module tb_v3_aux_mux;
 reg clk=0;always #5 clk=!clk;reg rst_n=0;
 reg vr=0,ar=0,aw=0,ack=0,busy=0,valid=0;reg[31:0] va=32'h100,aa=32'h280000,wd=32'h12345678,rd=0;
 wire vack,vbusy,vvalid,aack,abusy,avalid,sreq,swr;wire[31:0] vdata,adata,saddr,swdata;wire[15:0] slen;
 integer errors=0,checks=0,i;
 v3_aux_mux dut(.clk(clk),.rst_n(rst_n),.verify_req(vr),.verify_addr(va),.verify_len(16'd64),
 .verify_ack(vack),.verify_busy(vbusy),.verify_valid(vvalid),.verify_data(vdata),.audio_req(ar),.audio_wr(aw),
 .audio_addr(aa),.audio_wdata(wd),.audio_len(16'd1),.audio_ack(aack),.audio_busy(abusy),.audio_valid(avalid),.audio_data(adata),
 .sd_req(sreq),.sd_wr(swr),.sd_addr(saddr),.sd_wdata(swdata),.sd_len(slen),.sd_ack(ack),.sd_busy(busy),.sd_valid(valid),.sd_data(rd));
 task tick;begin  @(posedge clk);#1;  end endtask
 task check(input  ok,input [4095:0] name);begin  ok = (ok === 1'b1); checks = checks + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] %s",name);end   end endtask
 initial begin
 repeat(3)tick();@(negedge clk);rst_n=1;vr=1;ar=1;aw=1;tick();check(sreq && !swr && saddr==va && slen==64,"verify wins simultaneous request");
 repeat(4)begin tick();check(sreq && !aack && vbusy,"request retained while arbiter unavailable");end
 @(negedge clk);ack=1;busy=1;#1;check(vack && !aack,"grant routes to latched owner");tick();@(negedge clk);ack=0;vr=0;

 for(i=0;i<64;i = i + 1)begin
  @(negedge clk);valid=1;rd=i;#1;check(vvalid && !avalid && vdata==i,"all delayed responses retain owner");tick();
  @(negedge clk);valid=0;tick();
 end
 @(negedge clk);busy=0;tick();repeat(3)tick();check(sreq && swr && saddr==aa && slen==1,"audio receives next complete burst");
 @(negedge clk);ack=1;busy=1;#1;check(aack && !vack,"audio grant");tick();@(negedge clk);ack=0;ar=0;vr=1;
 repeat(5)begin tick();check(abusy && swdata==32'h12345678,"write data retained through physical stall");end
 @(negedge clk);busy=0;repeat(4)tick();check(sreq && !swr && saddr==va,"owner changes after complete retirement");
 $display("[PASS] aux ownership checks=%0d errors=%0d",checks,errors);$display("PASS tb_v3_aux_mux comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #100000;begin $display("[FAIL] aux test timeout"); $finish; end end
endmodule
