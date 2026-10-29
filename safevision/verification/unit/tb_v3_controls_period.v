`timescale 1ns/1ps
module tb_v3_controls_period;
 reg clk=0;always #5 clk=!clk;reg rst_n=0,cv=0;reg[95:0] name=0;reg[31:0] value=0;
 wire auto_on,auto_tick;wire[1:0] period;integer ticks=0,errors=0,checks=0,guard;
 v3_user_controls #(.CLK_HZ(100),.DEBOUNCE(3)) dut(.clk(clk),.rst_n(rst_n),
 .next_async(1'b1),.auto_async(1'b1),.emergency_async(1'b1),.command_valid(cv),
 .command_target(8'd67),.command_name(name),.command_value(value),.command_query(1'b0),
 .cached(1'b1),.transition_busy(1'b0),.frame_commit(1'b0),.auto_enabled(auto_on),
 .period_select(period),.auto_tick(auto_tick));
 always @(posedge clk)begin #1;if(auto_tick)ticks = ticks + 1;end
 task waitn(input integer n);begin repeat(n)@(negedge clk); end endtask
 task command(input[95:0] nm,input[31:0] v);begin begin name=nm;value=v;cv=1;waitn(1);cv=0;end  end endtask
 task check(input  ok,input [4095:0] label);begin begin ok = (ok === 1'b1); checks = checks + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] %s ticks=%0d seconds=%0d",label,ticks,dut.seconds);end else $display("[PASS] %s",label);end  end endtask
 initial begin
 waitn(4);rst_n=1;waitn(8);command("PERIOD",30);command("AUTO",1);
 guard=0;while(dut.seconds!=10 && guard<1200)begin waitn(1);guard = guard + 1;end
 check(dut.seconds==10 && ticks==0,"30-second countdown reaches ten seconds without early swap");
 command("PERIOD",2);waitn(205);
 check(period==0 && ticks==1,"running 30-to-2-second period change restarts countdown");
 command("PERIOD",5);waitn(505);
 check(period==1 && ticks==2,"running 2-to-5-second change uses a fresh five-second interval");
 $display("PASS tb_v3_controls_period comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #100000;begin $display("[FAIL] period-change test timeout"); $finish; end end
endmodule
