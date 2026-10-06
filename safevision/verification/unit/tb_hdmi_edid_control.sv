`timescale 1ns/1ps
module tb_hdmi_edid_control;
 reg clk=0,rst=0,hpd=0,reread=0;always #5 clk=~clk;
 wire trig,connected,txreset;
 hdmi_edid_control #(.SETTLE_CYCLES(9)) dut(.clk(clk),.rst_n(rst),.hpd(hpd),.reread(reread),.trigger(trig),.connected(connected),.tx_reset(txreset));
 integer pulses=0;reg prior=0;
 always @(posedge clk)begin #0.1;
  if(trig)begin
   if(prior||!connected||txreset)$fatal(1,"bad EDID trigger");pulses=pulses+1;
  end
  prior=trig;
 end
 task settle;begin repeat(25)@(negedge clk);end endtask
 initial begin
  #33;rst=1;settle();if(pulses!=0||!txreset)$fatal(1,"disconnected EDID request");
  #1.3;hpd=1;settle();if(pulses!=1||txreset)$fatal(1,"HPD insertion");
  reread=1;settle();if(pulses!=2)$fatal(1,"explicit EDID reread");
  settle();if(pulses!=2)$fatal(1,"held request repeated");reread=0;
  #2.2;hpd=0;settle();if(!txreset||connected)$fatal(1,"HPD removal");
  hpd=1;settle();if(pulses!=3)$fatal(1,"hotplug did not retrigger");
  hpd=0;settle();hpd=1;repeat(4)@(negedge clk);rst=0;
  repeat(5)@(negedge clk);rst=1;settle();if(pulses!=4)$fatal(1,"reset pending EDID");
  $display("PASS tb_hdmi_edid_control insertion/removal/held request/reinsert/reset pulses=%0d",pulses);$finish;
 end
 initial begin #100000;$fatal(1,"EDID watchdog");end
endmodule
