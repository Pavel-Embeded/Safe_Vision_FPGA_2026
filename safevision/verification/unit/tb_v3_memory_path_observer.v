`timescale 1ns/1ps
module tb_v3_memory_path_observer;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg sa=0,pw=0,start=0,rv=0,hv=0;
 reg[31:0]addr=0,sd=0,wd=0,rd=0,hd=0;reg[20:0]wa=0;reg[3:0]dm=0;
 wire[31:0]so,wo,ro,ho,wrong_ro;wire[8:0]sc,wc,rc,hc;
 v3_memory_path_observer dut(.clk(clk),.rst_n(rst_n),.source_accept(sa),.source_byte_addr(addr),.source_data(sd),
 .physical_write(pw),.physical_word_addr(wa),.physical_dm(dm),.physical_write_data(wd),
 .verify_start(start),.physical_read_valid(rv),.physical_read_data(rd),.host_read_valid(hv),.host_read_data(hd),
 .source_or(so),.write_or(wo),.raw_or(ro),.host_or(ho),.source_count(sc),.write_count(wc),.raw_count(rc),.host_count(hc));
 v3_memory_path_observer #(.READ_DATA_LEADS_VALID(0)) negative_alignment(
 .clk(clk),.rst_n(rst_n),.source_accept(sa),.source_byte_addr(addr),.source_data(sd),
 .physical_write(pw),.physical_word_addr(wa),.physical_dm(dm),.physical_write_data(wd),
 .verify_start(start),.physical_read_valid(rv),.physical_read_data(rd),.host_read_valid(hv),.host_read_data(hd),
 .source_or(),.write_or(),.raw_or(wrong_ro),.host_or(),.source_count(),.write_count(),.raw_count(),.host_count());
 integer errors=0,comparisons=0,i;
 task ck(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;
  if(!ok)begin errors = errors + 1;$display("[FAIL] %s",msg);end
  else $display("[PASS] %s",msg);
   end endtask
 task tick;begin  @(posedge clk);#1;@(negedge clk);  end endtask
 task reset_epoch;begin  rst_n=0;sa=0;pw=0;start=0;rv=0;hv=0;tick();rst_n=1;tick();  end endtask
 initial begin
  reset_epoch();

  rv=1;hv=1;rd=32'hdeadbeef;hd=32'hbadcafe;repeat(10)tick();rv=0;hv=0;
  ck(rc==0&&hc==0&&ro==0&&ho==0,"read window is not armed by unrelated earlier traffic");

  sa=1;pw=1;sd=-1;wd=-1;addr=32'h80000000;wa=0;dm=15;tick();
  addr=1;wa=320;dm=0;tick();sa=0;pw=0;
  ck(sc==0&&wc==0&&so==0&&wo==0,"full byte address, alignment, range and DQM filters");

  for(i=0;i<320;i = i + 1)begin
   sa=1;pw=1;addr=i*4;wa=i;dm=0;sd=0;wd=0;tick();
   sa=0;pw=1;wa=i+1;dm=15;wd=-1;tick();pw=0;repeat(i%3)tick();
  end
  ck(sc==320&&wc==320&&so==0&&wo==0,"exactly320 zero source/real-write words; padding ignored");
  start=1;rd=0;tick();start=0;

  for(i=0;i<=320;i = i + 1)begin
   rd=(i==320) ? 32'h80000000:0;rv=(i!=0);hv=(i!=0);hd=0;tick();
  end
  rv=0;hv=0;tick();
  ck(rc==320&&hc==320&&ro==0&&ho==0,"all320 correctly aligned raw/host words are zero");
  ck(wrong_ro==1,"alignment negative control observes tail poison");
  sa=1;pw=1;addr=0;wa=0;dm=0;sd=-1;wd=-1;rv=1;hv=1;rd=-1;hd=-1;repeat(12)tick();
  ck(sc==320&&wc==320&&rc==320&&hc==320&&so==0&&wo==0&&ro==0&&ho==0,"all windows saturate and freeze after320 words");
  reset_epoch();
  ck(sc==0&&wc==0&&rc==0&&hc==0&&so==0&&wo==0&&ro==0&&ho==0,"media reset clears counts and evidence together");
  start=1;tick();start=0;sa=1;pw=1;dm=0;

  for(i=0;i<=320;i = i + 1)begin
   addr=i*4;wa=i;sd=0;wd=0;rd=0;rv=i!=0;hv=i!=0;hd=(i==17) ? 32'h02000000:0;tick();
  end
  sa=0;pw=0;rv=0;hv=0;tick();
  ck(sc==320&&wc==320&&rc==320&&hc==320&&so==0&&wo==0&&ro==0&&ho==1,"host-only one-bit fault is localized after raw storage");
  reset_epoch();start=1;tick();start=0;
  for(i=0;i<=320;i = i + 1)begin rd=(i==4) ? 32'h00000040:0;rv=i!=0;hv=i!=0;hd=0;tick();end
  rv=0;hv=0;tick();
  ck(ro==1&&ho==0&&rc==320&&hc==320,"raw-only one-bit fault is reported independently");
  for(i=0;i<32;i = i + 1)begin
   reset_epoch();start=1;rd=32'd1<<i;tick();start=0;
   sa=1;pw=1;addr=0;wa=0;dm=0;sd=32'd1<<i;wd=32'd1<<i;
   rv=1;hv=1;hd=32'd1<<i;rd=0;tick();sa=0;pw=0;rv=0;hv=0;
   ck(sc==1&&wc==1&&rc==1&&hc==1&&so==1&&wo==1&&ro==1&&ho==1,"every32-bit position is observed by compact nonzero flags");
  end
  $display("[TB] tb_v3_memory_path_observer done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] observer watchdog errors=1");$finish;end
endmodule
