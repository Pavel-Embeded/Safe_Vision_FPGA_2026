// Independent elapsed-clock bounds for the production shared-tick mechanism.
`timescale 1ns/1ps
module tb_v3_supervisor_tick;
 reg clk=0;always #5 clk=!clk;
 reg rst_n=0,active=0,heartbeat=0;wire push;wire[7:0] code;wire[3:0] src;
 integer checks=0,errors=0,p,n,elapsed;
 v3_supervisor #(.CLK_HZ(10000),.BOOT_CYCLES(1000),.FRAME_CYCLES(80),
 .MEM_CYCLES(120),.PROGRESS_CYCLES(150),.RECOVER_CYCLES(800)) dut(
 .clk(clk),.rst_n(rst_n),.manual_safe(1'b0),.recover_request(1'b0),.cache_ready(1'b1),
 .media_failed(1'b0),.media_code(8'd0),.integrity_fault(1'b0),.bus_fault(1'b0),.fatal(1'b0),
 .frame_heartbeat(1'b1),.mem_heartbeat(heartbeat),.progress_heartbeat(1'b0),
 .memory_active(active),.media_active(1'b0),.video_underflows(32'd0),.audio_underflows(32'd0),
 .hdmi_drops(32'd0),.rejected_files(16'd0),.audio_fallback(4'd0),
 .err_push(push),.err_code(code),.err_src(src));
 task tick;begin @(posedge clk);#1;end endtask
 task check(input bit ok,input string name);begin checks++;if(!ok)begin errors++;$display("[FAIL] %s phase=%0d elapsed=%0d",name,p,elapsed);end end endtask
 task restart;begin @(negedge clk);rst_n=0;active=0;heartbeat=0;repeat(3)tick();@(negedge clk);rst_n=1;end endtask
 initial begin
  // Exercise all 10 positions of a heartbeat/arm edge relative to the tick.
  for(p=0;p<10;p++)begin
   restart();repeat(p)tick();@(negedge clk);active=1;elapsed=0;
   while(!push && elapsed<140)begin tick();elapsed++;end
   check(push && code==2 && src==5,"armed watchdog reports the true memory progress cause");
   check(elapsed>=111 && elapsed<=121,"expiry bounded by 120 clocks with less than one tick quantization");
  end
  restart();active=1;
  // A heartbeat exactly on the nominal 120-clock expiry wins over timeout.
  for(n=0;n<720;n++)begin
   heartbeat=(n%120==119);tick();check(!push,"heartbeat at expiry does not enqueue a false watchdog event");
   @(negedge clk);
  end
  active=0;heartbeat=0;repeat(300)begin tick();check(!push,"idle memory does not arm the divided watchdog");end
  $display("[PASS] shared tick phases and expiry heartbeat boundary");
  $display("PASS tb_v3_supervisor_tick comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #100000;$fatal(1,"tick watchdog test timeout");end
endmodule
