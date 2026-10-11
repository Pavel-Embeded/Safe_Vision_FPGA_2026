`timescale 1ns/1ps
module tb_board_play_control;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,manual=0,down=0,ready=1;wire pulse,en;wire [1:0] period;
 integer events=0,checks=0;
 board_play_control #(.SECOND_CYCLES(20)) dut(.clk(clk),.rst_n(rst),
 .manual_next(manual),.auto_down(down),.ready(ready),.auto_next(pulse),.enabled(en),.period(period));
 always @(negedge clk)if(pulse)events=events+1;
 task check(input bit condition,input string message);
 begin checks=checks+1;if(!condition)$fatal(1,"CONTROL: %s",message);end endtask
 task short_press;
 begin @(negedge clk);down=1;repeat(5)@(negedge clk);down=0;repeat(3)@(negedge clk);end endtask
 task long_press;
 begin @(negedge clk);down=1;repeat(25)@(negedge clk);down=0;repeat(3)@(negedge clk);end endtask
 integer n,before_n;
 initial begin
   repeat(4)@(negedge clk);rst=1;repeat(50)@(negedge clk);
   check(!en&&events==0&&period==0,"manual is boot default");short_press;
   check(en,"short press enables auto");wait(events==1);
   check(dut.timer<=1,"interval pulses once");ready=0;before_n=events;
   repeat(120)@(negedge clk);check(events==before_n,"busy phases do not emit or queue auto changes");
   ready=1;repeat(10)@(negedge clk);manual=1;@(negedge clk);manual=0;
   repeat(35)@(negedge clk);check(events==before_n,"manual change restarts full two-second interval");
   wait(events==before_n+1);ready=0;
   for(n=1;n<=4;n=n+1)begin
     long_press;check(en&&period==(n&3),"long press changes period once without toggling auto");
   end
   short_press;check(!en,"second short press disables auto");ready=1;
   before_n=events;repeat(100)@(negedge clk);check(events==before_n,"disabled auto emits no pulse");
   $display("PASS tb_board_play_control checks=%0d: manual/auto/2-5-10-30/busy/long-hold",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"CONTROL watchdog");end
endmodule
