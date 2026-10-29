`timescale 1ns/1ps
module control_clock_case776 #(parameter HD=0,HZ=50000000)(input clk,output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 reg rst_n=0,rxd=1;integer received=0;realtime origin,period;integer k;
 safevision_v3_top #(.HD(HD)) dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(rxd),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 task check(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons=comparisons+1;if(!ok)begin errors=errors+1;$display("[FAIL] HD=%0d %s",HD,msg);end end  end endtask
 function[7:0] expected_byte(input integer n);begin begin case(n)0:expected_byte=8'h55;1:expected_byte=8'ha6;default:expected_byte=8'h00;endcase end  end endfunction
 task send_byte(input[7:0] b);integer n;begin begin
  rxd=0;#8680.555556;
  for(n=0;n<8;n=n+1)begin rxd=b[n];#8680.555556;end
  rxd=1;#17361.111112;
 end  end endtask
 always @(posedge dut.sys_clk)begin #1;
  if(dut.sys_rst_n && dut.uart.byte_valid)begin
   check(received<3 && dut.uart.byte_rx===expected_byte(received),"real115200baud UART byte order and data");received=received+1;
  end
 end
 initial begin
  repeat(10)@(negedge clk);rst_n=1;wait(dut.sys_rst_n);repeat(5)@(negedge dut.sys_clk);
  @(posedge dut.sys_clk);origin=$realtime;repeat(20)@(posedge dut.sys_clk);period=($realtime-origin)/20.0;
  check(period>1.0e9/HZ-0.001 && period<1.0e9/HZ+0.001,"actual selected SYS wire period from explicit PLL clock-contract model");
  check(dut.SYS_HZ==HZ && dut.controls.CLK_HZ==HZ,"control frequency parameter propagation");
  check(dut.controls.DEBOUNCE==HZ/50 && dut.controls.UI_DIV==HZ/1000 && dut.controls.UI_SECOND==1000,"20ms debounce and1ms control tick");
  check(dut.uart.CLK_HZ==HZ && dut.uart.rx.CLK_HZ==HZ && dut.uart.tx.CLK_FREQ==HZ,"RX and TX physical baud divider calibration");
  check(dut.supervisor.CLK_HZ==HZ && dut.supervisor.FRAME_LIMIT==100 && dut.supervisor.MEM_LIMIT==200 && dut.supervisor.PROGRESS_LIMIT==500,"100ms frame200ms memory500ms progress watchdogs");
  check(dut.supervisor.BOOT_LIMIT==60000 && dut.supervisor.WINDOW_LIMIT==1000 && dut.supervisor.RECOVER_CYCLES==HZ/10*49,"60s boot1s window4.9s recovery");
  check(dut.response_timer.CLK_HZ==HZ && dut.response_timer.TICKS==HZ/1000,"response milliseconds use actual domain frequency");

  force dut.response_timer.cancel=1'b0;force dut.response_timer.start=1'b1;force dut.response_timer.finish=1'b0;
  @(posedge dut.sys_clk);#1;check(dut.response_timer.active && dut.response_timer.cycles==0,"timer public start");
  @(negedge dut.sys_clk);force dut.response_timer.start=1'b0;dut.response_timer.cycles=HZ/1000-2;
  @(posedge dut.sys_clk);#1;check(dut.response_timer.milliseconds==0,"one edge before1ms boundary");
  @(negedge dut.sys_clk);force dut.response_timer.finish=1'b1;
  @(posedge dut.sys_clk);#1;check(dut.response_latency_ms==1 && !dut.response_timer.active,"coincident finish includes exact1ms tick once");
  @(negedge dut.sys_clk);release dut.response_timer.start;release dut.response_timer.finish;release dut.response_timer.cancel;
  send_byte(8'h55);send_byte(8'ha6);send_byte(8'h00);#20000;
  check(received==3,"all three real-baud bytes received");
  check(dut.uart.rx_framing==0 && dut.uart.rx_overrun==0,"zero framing and overrun errors");
  done=1;
 end
endmodule
module tb_v3_control_clock776;
 reg clk=0;always #10 clk=~clk;wire d0,d1;wire[31:0] e0,e1,c0,c1;integer errors,comparisons;
 control_clock_case776 #(.HD(0),.HZ(50000000)) base(clk,d0,e0,c0);
 control_clock_case776 #(.HD(1),.HZ(100000000)) hd(clk,d1,e1,c1);
 initial begin wait(d0&&d1);#2;errors=e0+e1;comparisons=c0+c1;
  if(errors==0)$display("[PASS] actual selected BASE50/HD100 control clock wiring, calibrated time units and real-baud RX");
  $display("[TB] tb_v3_control_clock776 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] control clock watchdog errors=1");$display("[TB] tb_v3_control_clock776 done errors=1 comparisons=0");$finish;end
endmodule
