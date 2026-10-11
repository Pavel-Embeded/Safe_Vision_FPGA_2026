`timescale 1ns/1ps
module tb_file_index_window;
 reg clk=0;always #10 clk=~clk;reg rst=0,clear=0,commit=0,valid=0;
 reg [15:0] after=0;reg [87:0] name83=0;reg [31:0] cluster=0;reg [1:0] sel=0;
 wire [31:0] selected;wire [15:0] maximum;wire [3:0] count;wire done;
 file_index #(.WINDOW_SCAN(1)) dut(.clk(clk),.rst_n(rst),.after_key(after),.max_key(maximum),
 .ent_name(name83),.ent_attr(8'h20),.ent_first_clus(cluster),.ent_size(32'd921654),.ent_index(16'd0),.ent_valid(valid),
 .idx_clear(clear),.idx_commit(commit),.idx_done(done),.file_cnt(count),.sel_slot(sel),.sel_first_clus(selected));
 task entry(input [87:0] name_in,input [31:0] cluster_in);
 begin @(negedge clk);name83=name_in;cluster=cluster_in;valid=1;@(negedge clk);valid=0;end endtask
 task scan;
 begin
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  entry("SV0006  BMP",6);entry("SV0002  BMP",2);entry("SV0005  BMP",5);
  entry("SV0001  BMP",1);entry("SV0007  BMP",7);entry("SV0004  BMP",4);entry("SV0003  BMP",3);
  repeat(5)@(negedge clk);commit=1;@(negedge clk);commit=0;wait(done);@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;scan;
  if(count!=4||maximum!=16'h0004)$fatal(1,"first sorted window");
  after=maximum;scan;
  if(count!=3||maximum!=16'h0007)$fatal(1,"refill window excludes all earlier candidates");
  for(integer n=0;n<3;n=n+1)begin sel=n;#1;if(selected!=n+5)$fatal(1,"refill numeric order");end
  after=maximum;scan;if(count!=0)$fatal(1,"directory end terminates refill");
  $display("PASS tb_file_index_window checks=6: sorted windows / monotonic boundary / directory end");$finish;
 end
 initial begin #20000;$fatal(1,"window watchdog");end
endmodule
