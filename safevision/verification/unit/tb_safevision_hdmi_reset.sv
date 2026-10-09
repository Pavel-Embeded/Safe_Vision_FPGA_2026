// Full-top EDID trigger regression. IP models are contracts, not DDC/HDMI
// electrical simulation. Fault injection resets the actual top-level timer.
`timescale 1ns/1ps
module tb_safevision_hdmi_reset;
 reg clk=0,rst_n=0; always #10 clk=~clk;
 wire uart_txd; wire [3:0] led;
 wire sd_ncs,sd_dclk,sd_mosi;
 wire HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,HDMI_CLK_P,HDMI_DDC_SCL;
 tri HDMI_DDC_SDA;
 safevision_top #(.HD(0),.FONT_FILE("font8x16.mem")) dut(
  .clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),
  .uart_txd(uart_txd),.led(led),.sd_ncs(sd_ncs),.sd_dclk(sd_dclk),
  .sd_mosi(sd_mosi),.sd_miso(1'b1),.HDMI_D0_P(HDMI_D0_P),
  .HDMI_D1_P(HDMI_D1_P),.HDMI_D2_P(HDMI_D2_P),.HDMI_CLK_P(HDMI_CLK_P),
  .HDMI_DDC_SCL(HDMI_DDC_SCL),.HDMI_DDC_SDA(HDMI_DDC_SDA));
 integer triggers=0,checks=0;
 always @(posedge dut.pixel_clk) begin
  #0.2;
  if(dut.edid_trig===1'b1)begin
   if(dut.tx_reset!==1'b0)$fatal(1,"EDID trigger during transmitter reset");
   triggers=triggers+1;
  end
 end
 // Called at a negative edge following reset release. Count interface cycles,
 // independently of the implementation's counter and saturation behavior.
 task settling_then_trigger;
  integer i;
  begin
   for(i=1;i<=100000;i=i+1)begin
    @(posedge dut.pixel_clk);#0.5;checks=checks+1;
    if(dut.edid_trig !== (i==100000))
     $fatal(1,"EDID settling/trigger cycle=%0d trig=%b",i,dut.edid_trig);
   end
   repeat(20)begin @(posedge dut.pixel_clk);#0.5;
    if(dut.edid_trig!==0)$fatal(1,"EDID trigger repeated after settling");
   end
  end
 endtask
 task queue_reset;
  begin
   @(negedge dut.pixel_clk);force dut.hdmi_resync=1'b1;
   repeat(1)begin @(posedge dut.pixel_clk);#0.5;
    if(dut.edid_trig!==0)$fatal(1,"EDID not suppressed during reset");
   end
   @(negedge dut.pixel_clk);release dut.hdmi_resync;
  end
 endtask
 initial begin
  #200;rst_n=1;
  wait(dut.pixel_rst_n===1'b1);@(negedge dut.pixel_clk);
  settling_then_trigger;
  if(triggers!=1)$fatal(1,"initial EDID event count");
  queue_reset;settling_then_trigger;
  if(triggers!=2)$fatal(1,"resync did not re-read EDID");
  queue_reset;
  repeat(50000)begin @(posedge dut.pixel_clk);#0.5;
   if(dut.edid_trig!==0)$fatal(1,"early EDID during interrupted settling");
  end
  queue_reset;settling_then_trigger;
  if(triggers!=3)$fatal(1,"pending EDID epoch not restarted");
  @(negedge clk);rst_n=0;
  repeat(10)@(posedge clk);
  @(negedge clk);rst_n=1;
  wait(dut.pixel_rst_n===1'b1);@(negedge dut.pixel_clk);
  settling_then_trigger;
  if(triggers!=4)$fatal(1,"KEY1 reset EDID count");
  $display("[PASS] HDMI top EDID reset/re-read/interrupted settling/KEY1 checks=%0d triggers=%0d",checks,triggers);
  $finish;
 end
 initial begin #30000000;$fatal(1,"EDID reset watchdog");end
endmodule
