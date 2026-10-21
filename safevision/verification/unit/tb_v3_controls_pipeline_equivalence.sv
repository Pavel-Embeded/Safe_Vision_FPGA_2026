`timescale 1ns/1ps
module tb_v3_controls_pipeline_equivalence;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg[31:0]rng=32'hc1261801;integer k,errors=0,comparisons=0;
 function[31:0]rand32;begin rng=rng*1664525+1013904223;rand32=rng;end endfunction
 reg  next_async=0;
 reg  auto_async=0;
 reg  emergency_async=0;
 reg  command_valid=0;
 reg  prev_command_valid=0;
 reg [7:0] command_target=0;
 reg [7:0] prev_command_target=0;
 reg [95:0] command_name=0;
 reg [95:0] prev_command_name=0;
 reg [31:0] command_value=0;
 reg [31:0] prev_command_value=0;
 reg  command_query=0;
 reg  prev_command_query=0;
 reg  cached=0;
 reg  transition_busy=0;
 reg  frame_commit=0;
 reg  system_safe=0;
 reg [6:0] catalog_id=0;
 reg [6:0] prev_catalog_id=0;
 reg  config_rst_n=0;
 wire  a_next_request,b_next_request;
 wire  a_auto_enabled,b_auto_enabled;
 wire  a_safety,b_safety;
 wire  a_recover_request,b_recover_request;
 wire  a_reply_valid,b_reply_valid;
 wire [7:0] a_reply_code,b_reply_code;
 wire [31:0] a_reply_value,b_reply_value;
 wire [8:0] a_brightness,b_brightness;
 wire [7:0] a_contrast,b_contrast;
 wire [7:0] a_osd_alpha,b_osd_alpha;
 wire  a_bilinear,b_bilinear;
 wire  a_fit,b_fit;
 wire  a_fade_enabled,b_fade_enabled;
 wire [6:0] a_volume,b_volume;
 wire [1:0] a_period_select,b_period_select;
 wire  a_menu,b_menu;
 wire [2:0] a_field,b_field;
 wire  a_auto_tick,b_auto_tick;
 wire [6:0] a_brightness_pct,b_brightness_pct;
 wire  a_brightness_raw,b_brightness_raw;
 wire [1:0] a_scale_select,b_scale_select;
 always@(posedge clk or negedge rst_n)begin if(!rst_n)begin prev_command_query<=0;prev_command_name<=0;prev_catalog_id<=0;prev_command_value<=0;prev_command_target<=0;prev_command_valid<=0;end else begin prev_command_query<=command_query;prev_command_name<=command_name;prev_catalog_id<=catalog_id;prev_command_value<=command_value;prev_command_target<=command_target;prev_command_valid<=command_valid;end end
 v3_user_controls #(.CLK_HZ(100),.DEBOUNCE(2),.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) a(.clk(clk),.rst_n(rst_n),.next_async(next_async),.auto_async(auto_async),.emergency_async(emergency_async),.command_valid(command_valid),.command_target(command_target),.command_name(command_name),.command_value(command_value),.command_query(command_query),.cached(cached),.transition_busy(transition_busy),.frame_commit(frame_commit),.system_safe(system_safe),.catalog_id(catalog_id),.config_rst_n(config_rst_n),.next_request(a_next_request),.auto_enabled(a_auto_enabled),.safety(a_safety),.recover_request(a_recover_request),.reply_valid(a_reply_valid),.reply_code(a_reply_code),.reply_value(a_reply_value),.brightness(a_brightness),.contrast(a_contrast),.osd_alpha(a_osd_alpha),.bilinear(a_bilinear),.fit(a_fit),.fade_enabled(a_fade_enabled),.volume(a_volume),.period_select(a_period_select),.menu(a_menu),.field(a_field),.auto_tick(a_auto_tick),.brightness_pct(a_brightness_pct),.brightness_raw(a_brightness_raw),.scale_select(a_scale_select));
 v3_controls_pipeline_reference #(.CLK_HZ(100),.DEBOUNCE(2),.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) b(.clk(clk),.rst_n(rst_n),.next_async(next_async),.auto_async(auto_async),.emergency_async(emergency_async),.command_valid(prev_command_valid),.command_target(prev_command_target),.command_name(prev_command_name),.command_value(prev_command_value),.command_query(prev_command_query),.cached(cached),.transition_busy(transition_busy),.frame_commit(frame_commit),.system_safe(system_safe),.catalog_id(prev_catalog_id),.config_rst_n(config_rst_n),.next_request(b_next_request),.auto_enabled(b_auto_enabled),.safety(b_safety),.recover_request(b_recover_request),.reply_valid(b_reply_valid),.reply_code(b_reply_code),.reply_value(b_reply_value),.brightness(b_brightness),.contrast(b_contrast),.osd_alpha(b_osd_alpha),.bilinear(b_bilinear),.fit(b_fit),.fade_enabled(b_fade_enabled),.volume(b_volume),.period_select(b_period_select),.menu(b_menu),.field(b_field),.auto_tick(b_auto_tick),.brightness_pct(b_brightness_pct),.brightness_raw(b_brightness_raw),.scale_select(b_scale_select));
 always@(posedge clk)begin #1;if(rst_n&&config_rst_n)begin comparisons++;if({a_next_request,a_auto_enabled,a_safety,a_recover_request,a_reply_valid,a_reply_code,a_reply_value,a_brightness,a_contrast,a_osd_alpha,a_bilinear,a_fit,a_fade_enabled,a_volume,a_period_select,a_menu,a_field,a_auto_tick,a_brightness_pct,a_brightness_raw,a_scale_select}!=={b_next_request,b_auto_enabled,b_safety,b_recover_request,b_reply_valid,b_reply_code,b_reply_value,b_brightness,b_contrast,b_osd_alpha,b_bilinear,b_fit,b_fade_enabled,b_volume,b_period_select,b_menu,b_field,b_auto_tick,b_brightness_pct,b_brightness_raw,b_scale_select})begin errors++;if(errors<12)$display("[FAIL] full controls contract with precisely one registered command edge cycle%0d",comparisons);end end end
 initial begin
 next_async=1;auto_async=1;emergency_async=1;cached=1;
 repeat(4)@(negedge clk);config_rst_n=1;rst_n=1;
 for(k=0;k<600000;k++)begin
  command_valid=rand32()%4!=0;command_query=rand32()%2;catalog_id=rand32()%44;
  command_target=65+rand32()%4;command_value=rand32();
  case(k%16)0:command_value=-128;1:command_value=127;2:command_value=128;3:command_value=255;
   4:command_value=256;5:command_value=513;6:command_value=-511;7:command_value=1;8:command_value=0;
   9:command_value=2;10:command_value=5;11:command_value=10;12:command_value=30;13:command_value=100;
   14:command_value=-256;default:;endcase
  cached=rand32()%8!=0;transition_busy=rand32()%8==0;frame_commit=rand32()%128==0;system_safe=rand32()%64==0;
  if(k%97==0)begin next_async=rand32()%2;auto_async=rand32()%2;emergency_async=rand32()%2;end
  rst_n=k%1009!=0;config_rst_n=k%10007!=0;
  @(negedge clk);
 end
 if(errors==0)$display("[PASS]600000 back-to-back/full32-bit command vectors, invalid aliases513/-511, keys, warm/power reset; exact public contract plus one command edge");
 $display("[TB] tb_v3_controls_pipeline_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
