`timescale 1ns/1ps
module tb_v3_control_decode_equivalence;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 reg next_async=1,auto_async=1,emergency_async=1,command_valid=0,command_query=0;
 reg[7:0] command_target=65;reg[95:0] command_name="BRIGHT";
 reg signed[31:0] command_value=0;reg cached=1,transition_busy=0,frame_commit=0;
 reg[31:0] rng=32'hc573e281;integer i,j,errors=0,comparisons=0;
 wire a_next_request;
 wire a_auto_enabled;
 wire a_safety;
 wire a_recover_request;
 wire a_reply_valid;
 wire[7:0] a_reply_code;
 wire[31:0] a_reply_value;
 wire[8:0] a_brightness;
 wire[7:0] a_contrast;
 wire[7:0] a_osd_alpha;
 wire a_bilinear;
 wire a_fit;
 wire a_fade_enabled;
 wire[6:0] a_volume;
 wire[1:0] a_period_select;
 wire a_menu;
 wire[2:0] a_field;
 wire a_auto_tick;
 wire e_next_request;
 wire e_auto_enabled;
 wire e_safety;
 wire e_recover_request;
 wire e_reply_valid;
 wire[7:0] e_reply_code;
 wire[31:0] e_reply_value;
 wire[8:0] e_brightness;
 wire[7:0] e_contrast;
 wire[7:0] e_osd_alpha;
 wire e_bilinear;
 wire e_fit;
 wire e_fade_enabled;
 wire[6:0] e_volume;
 wire[1:0] e_period_select;
 wire e_menu;
 wire[2:0] e_field;
 wire e_auto_tick;
 v3_user_controls #(.CLK_HZ(32),.DEBOUNCE(2)) dut(
 .clk(clk),.rst_n(rst_n),.next_async(next_async),.auto_async(auto_async),.emergency_async(emergency_async),.command_valid(command_valid),.command_target(command_target),.command_name(command_name),.command_value(command_value),.command_query(command_query),.cached(cached),.transition_busy(transition_busy),.frame_commit(frame_commit),
 .next_request(a_next_request),.auto_enabled(a_auto_enabled),.safety(a_safety),.recover_request(a_recover_request),.reply_valid(a_reply_valid),.reply_code(a_reply_code),.reply_value(a_reply_value),.brightness(a_brightness),.contrast(a_contrast),.osd_alpha(a_osd_alpha),.bilinear(a_bilinear),.fit(a_fit),.fade_enabled(a_fade_enabled),.volume(a_volume),.period_select(a_period_select),.menu(a_menu),.field(a_field),.auto_tick(a_auto_tick));
 v3_user_controls_reference #(.CLK_HZ(32),.DEBOUNCE(2)) reference(
 .clk(clk),.rst_n(rst_n),.next_async(next_async),.auto_async(auto_async),.emergency_async(emergency_async),.command_valid(command_valid),.command_target(command_target),.command_name(command_name),.command_value(command_value),.command_query(command_query),.cached(cached),.transition_busy(transition_busy),.frame_commit(frame_commit),
 .next_request(e_next_request),.auto_enabled(e_auto_enabled),.safety(e_safety),.recover_request(e_recover_request),.reply_valid(e_reply_valid),.reply_code(e_reply_code),.reply_value(e_reply_value),.brightness(e_brightness),.contrast(e_contrast),.osd_alpha(e_osd_alpha),.bilinear(e_bilinear),.fit(e_fit),.fade_enabled(e_fade_enabled),.volume(e_volume),.period_select(e_period_select),.menu(e_menu),.field(e_field),.auto_tick(e_auto_tick));
 task sample;begin
  @(posedge clk);#0.001;comparisons=comparisons+5;
  if({a_next_request,a_auto_enabled,a_safety,a_recover_request,a_reply_valid,a_reply_code,a_reply_value,a_brightness,a_contrast,a_osd_alpha,a_bilinear,a_fit,a_fade_enabled,a_volume,a_period_select,a_menu,a_field,a_auto_tick}!=={e_next_request,e_auto_enabled,e_safety,e_recover_request,e_reply_valid,e_reply_code,e_reply_value,e_brightness,e_contrast,e_osd_alpha,e_bilinear,e_fit,e_fade_enabled,e_volume,e_period_select,e_menu,e_field,e_auto_tick})begin errors=errors+1;if(errors<10)$display("[FAIL] controls differ cycle=%0d name=%s value=%0d valid=%0b query=%0b bright=%h/%h contrast=%h/%h reply=%h/%h state=%h/%h",i,command_name,command_value,command_valid,command_query,a_brightness,e_brightness,a_contrast,e_contrast,{a_reply_valid,a_reply_code,a_reply_value},{e_reply_valid,e_reply_code,e_reply_value},{a_next_request,a_auto_enabled,a_safety,a_recover_request,a_osd_alpha,a_bilinear,a_fit,a_fade_enabled,a_volume,a_period_select,a_menu,a_field,a_auto_tick},{e_next_request,e_auto_enabled,e_safety,e_recover_request,e_osd_alpha,e_bilinear,e_fit,e_fade_enabled,e_volume,e_period_select,e_menu,e_field,e_auto_tick});end
  if(dut.value_bright_ok!==(command_value>=-128 && command_value<=127))begin errors=errors+1;if(errors<10)$display("[FAIL] exact predicate value_bright_ok value=%0d",command_value);end
  if(dut.value_byte_ok!==(command_value>=0 && command_value<=255))begin errors=errors+1;if(errors<10)$display("[FAIL] exact predicate value_byte_ok value=%0d",command_value);end
  if(dut.value_bit_ok!==(command_value>=0 && command_value<=1))begin errors=errors+1;if(errors<10)$display("[FAIL] exact predicate value_bit_ok value=%0d",command_value);end
  if(dut.value_volume_ok!==(command_value>=0 && command_value<=100))begin errors=errors+1;if(errors<10)$display("[FAIL] exact predicate value_volume_ok value=%0d",command_value);end
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;


  for(i=0;i<1000000;i=i+1)begin
   @(negedge clk);rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   command_valid=(i%37!=0);command_query=rng[6];cached=rng[7];transition_busy=rng[8];frame_commit=(i%79==0);
   if(i%13==0)begin next_async=rng[9];auto_async=rng[10];emergency_async=rng[11];end
   command_target=65;
   case(i%12)
    0:begin command_name="BRIGHT";command_target=8'd65;end
    1:begin command_name="CONTRAST";command_target=8'd65;end
    2:begin command_name="ALPHA";command_target=8'd65;end
    3:begin command_name="SCALER";command_target=8'd65;end
    4:begin command_name="SCALE";command_target=8'd65;end
    5:begin command_name="FADE";command_target=8'd65;end
    6:begin command_name="VOL";command_target=8'd67;end
    7:begin command_name="PERIOD";command_target=8'd67;end
    8:begin command_name="AUTO";command_target=8'd67;end
    9:begin command_name="NEXT";command_target=8'd67;end
    10:begin command_name="RECOVER";command_target=8'd67;end
    11:begin command_name="UNKNOWN";command_target=rng[15:8];end
   endcase
   if(i<786432)command_value=$signed(16'((i/12)-32768));
   else case(i%17)
    0:command_value=-129;1:command_value=-128;2:command_value=127;3:command_value=128;
    4:command_value=-1;5:command_value=0;6:command_value=1;7:command_value=2;
    8:command_value=100;9:command_value=101;10:command_value=255;11:command_value=256;
    12:command_value=32'h80000000;13:command_value=32'h7fffffff;
    default:command_value=rng;
   endcase
   if(i%53==0)command_target=8'd66;
   if(i%40001==0)rst_n=0;else rst_n=1;
   sample;
  end
  if(errors==0)$display("[PASS] all controls public outputs and four exact32bit range predicates cycle exact");
  $display("[TB] tb_v3_control_decode_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #12000000;$display("[FAIL] controls oracle watchdog errors=1");$finish;end
endmodule
