`timescale 1ns/1ps
module tb_hdmi_edid_control;
 reg clk=0,rst=0,hpd=0,reread=0;always #5 clk=~clk;
 wire trig,connected,txreset;
 hdmi_edid_control #(.SETTLE_CYCLES(9)) dut(.clk(clk),.rst_n(rst),.hpd(hpd),.reread(reread),.trigger(trig),.connected(connected),.tx_reset(txreset));
 integer pulses=0;reg prior=0;
 always @(posedge clk)begin #0.1;
  if(trig)begin
   if(prior||!connected||txreset)begin $display("[FAIL] bad EDID trigger"); $finish; end pulses=pulses+1;
  end
  prior=trig;
 end
 task settle;begin  repeat(25)@(negedge clk);  end endtask
 initial begin
  #33;rst=1;settle();if(pulses!=0||!txreset)begin $display("[FAIL] disconnected EDID request"); $finish; end
  #1.3;hpd=1;settle();if(pulses!=1||txreset)begin $display("[FAIL] HPD insertion"); $finish; end
  reread=1;settle();if(pulses!=2)begin $display("[FAIL] explicit EDID reread"); $finish; end
  settle();if(pulses!=2)begin $display("[FAIL] held request repeated"); $finish; end reread=0;
  #2.2;hpd=0;settle();if(!txreset||connected)begin $display("[FAIL] HPD removal"); $finish; end
  hpd=1;settle();if(pulses!=3)begin $display("[FAIL] hotplug did not retrigger"); $finish; end
  hpd=0;settle();hpd=1;repeat(4)@(negedge clk);rst=0;
  repeat(5)@(negedge clk);rst=1;settle();if(pulses!=4)begin $display("[FAIL] reset pending EDID"); $finish; end
  $display("PASS tb_hdmi_edid_control insertion/removal/held request/reinsert/reset pulses=%0d",pulses);$finish;
 end
 initial begin #100000;begin $display("[FAIL] EDID watchdog"); $finish; end end
endmodule
