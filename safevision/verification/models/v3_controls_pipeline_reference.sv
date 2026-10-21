// Normal buttons are decoded on release, so a chord cannot leak a next/auto.
// Emergency is never gated by menu or UART. Configuration has one driver.
module v3_controls_pipeline_reference #(parameter integer CLK_HZ=100000000,DEBOUNCE=2000000,BOARD_CATALOG=0,SYSTEM_SAFE_ENABLE=0,
 HANDBOOK_PROFILE=0,DEFAULT_AUTO=0,RETAIN_CONFIG=0)(
 input wire clk,rst_n,next_async,auto_async,emergency_async,
 input wire command_valid,input wire [7:0] command_target,
 input wire [95:0] command_name,input wire signed [31:0] command_value,input wire command_query,
 input wire cached,transition_busy,frame_commit,system_safe,
 output reg next_request,output reg auto_enabled,output wire safety,
 output reg recover_request,output reg reply_valid,output reg [7:0] reply_code,
 output reg signed [31:0] reply_value,
 output reg signed [8:0] brightness,output reg [7:0] contrast,osd_alpha,
 output reg bilinear,fit,fade_enabled,output reg [6:0] volume,
 output reg [1:0] period_select,output reg menu,
 output reg [2:0] field,output reg auto_tick,input wire[6:0] catalog_id,
 input wire config_rst_n,output reg[6:0] brightness_pct,output reg brightness_raw,
 output reg[1:0] scale_select);
 localparam[95:0] NAME_BRIGHT="BRIGHT";
 localparam[95:0] NAME_CONTRAST="CONTRAST";
 localparam[95:0] NAME_ALPHA="ALPHA";
 localparam[95:0] NAME_SCALER="SCALER";
 localparam[95:0] NAME_SCALE="SCALE";
 localparam[95:0] NAME_FADE="FADE";
 localparam[95:0] NAME_VOL="VOL";
 localparam[95:0] NAME_PERIOD="PERIOD";
 localparam[95:0] NAME_AUTO="AUTO";
 localparam[95:0] NAME_NEXT="NEXT";
 localparam[95:0] NAME_RECOVER="RECOVER";
 localparam[95:0] NAME_BRTPC="BRTPC";
 localparam[95:0] NAME_SCALESEL="SCALESEL";
 localparam[95:0] NAME_MENU="MENU";
 localparam[95:0] NAME_FIELD="FIELD";
 localparam[3:0] OP_BRIGHT=4'd0;
 localparam[6:0] CTRL_ID_BRIGHT=7'd5;
 localparam[3:0] OP_CONTRAST=4'd1;
 localparam[6:0] CTRL_ID_CONTRAST=7'd7;
 localparam[3:0] OP_ALPHA=4'd2;
 localparam[6:0] CTRL_ID_ALPHA=7'd1;
 localparam[3:0] OP_SCALER=4'd3;
 localparam[6:0] CTRL_ID_SCALER=7'd25;
 localparam[3:0] OP_SCALE=4'd4;
 localparam[6:0] CTRL_ID_SCALE=7'd24;
 localparam[3:0] OP_FADE=4'd5;
 localparam[6:0] CTRL_ID_FADE=7'd9;
 localparam[3:0] OP_VOL=4'd6;
 localparam[6:0] CTRL_ID_VOL=7'd33;
 localparam[3:0] OP_PERIOD=4'd7;
 localparam[6:0] CTRL_ID_PERIOD=7'd18;
 localparam[3:0] OP_AUTO=4'd8;
 localparam[6:0] CTRL_ID_AUTO=7'd2;
 localparam[3:0] OP_NEXT=4'd9;
 localparam[6:0] CTRL_ID_NEXT=7'd16;
 localparam[3:0] OP_RECOVER=4'd10;
 localparam[6:0] CTRL_ID_RECOVER=7'd20;
 localparam[3:0] OP_BRTPC=4'd11;
 localparam[6:0] CTRL_ID_BRTPC=7'd37;
 localparam[3:0] OP_SCALESEL=4'd12;
 localparam[6:0] CTRL_ID_SCALESEL=7'd41;
 localparam[3:0] OP_MENU=4'd13;
 localparam[6:0] CTRL_ID_MENU=7'd40;
 localparam[3:0] OP_FIELD=4'd14;
 localparam[6:0] CTRL_ID_FIELD=7'd38;
 function[3:0] decode_name;input[95:0] name;begin decode_name=4'd15;case(name)
 NAME_BRIGHT:decode_name=OP_BRIGHT;
 NAME_CONTRAST:decode_name=OP_CONTRAST;
 NAME_ALPHA:decode_name=OP_ALPHA;
 NAME_SCALER:decode_name=OP_SCALER;
 NAME_SCALE:decode_name=OP_SCALE;
 NAME_FADE:decode_name=OP_FADE;
 NAME_VOL:decode_name=OP_VOL;
 NAME_PERIOD:decode_name=OP_PERIOD;
 NAME_AUTO:decode_name=OP_AUTO;
 NAME_NEXT:decode_name=OP_NEXT;
 NAME_RECOVER:decode_name=OP_RECOVER;
 NAME_BRTPC:decode_name=OP_BRTPC;
 NAME_SCALESEL:decode_name=OP_SCALESEL;
 NAME_MENU:decode_name=OP_MENU;
 NAME_FIELD:decode_name=OP_FIELD;
 default:;endcase end endfunction
 function[3:0] decode_catalog;input[6:0] id;begin decode_catalog=4'd15;case(id)
 CTRL_ID_BRIGHT:decode_catalog=OP_BRIGHT;
 CTRL_ID_CONTRAST:decode_catalog=OP_CONTRAST;
 CTRL_ID_ALPHA:decode_catalog=OP_ALPHA;
 CTRL_ID_SCALER:decode_catalog=OP_SCALER;
 CTRL_ID_SCALE:decode_catalog=OP_SCALE;
 CTRL_ID_FADE:decode_catalog=OP_FADE;
 CTRL_ID_VOL:decode_catalog=OP_VOL;
 CTRL_ID_PERIOD:decode_catalog=OP_PERIOD;
 CTRL_ID_AUTO:decode_catalog=OP_AUTO;
 CTRL_ID_NEXT:decode_catalog=OP_NEXT;
 CTRL_ID_RECOVER:decode_catalog=OP_RECOVER;
 CTRL_ID_BRTPC:decode_catalog=OP_BRTPC;
 CTRL_ID_SCALESEL:decode_catalog=OP_SCALESEL;
 CTRL_ID_MENU:decode_catalog=OP_MENU;
 CTRL_ID_FIELD:decode_catalog=OP_FIELD;
 default:;endcase end endfunction
 // The board catalog guarantees name/ID identity on command_valid.
 // Generic callers retain the complete original ASCII-name interface.
 wire[3:0] opcode=BOARD_CATALOG?decode_catalog(catalog_id):decode_name(command_name);
 // Exact two's-complement tests for all 2^32 input bit patterns. Command
 // decoding is independent of value validity, so one command's rejected
 // value cannot build a priority path to another command's enable.
 wire value_bright_ok=(~|command_value[31:7]) || (&command_value[31:7]);
 wire value_byte_ok=~|command_value[31:8];
 wire value_bit_ok=~|command_value[31:1];
 wire value_volume_ok=(~|command_value[31:7]) && command_value[6:0]<=7'd100;
 wire [2:0] levels,press;
 key_debounce #(.KEYS(3),.DEB_N(DEBOUNCE),.RESET_LEVEL(0)) buttons(
 .clk(clk),.rst_n(rst_n),.key_async({!emergency_async,!auto_async,!next_async}),
 .evt_clear(1'b1),.key_level(levels),.press_vec(press),.press_any(),.evt_key(),.evt_pending());
 assign safety=levels[2];
 reg [2:0] previous;reg [1:0] period_previous;
 localparam integer HOLD_W=(CLK_HZ>1)?$clog2(CLK_HZ+1):1;
 localparam integer CYCLE_W=(CLK_HZ>1)?$clog2(CLK_HZ):1;
 localparam integer CHORD_W=(CLK_HZ>1)?$clog2(2*CLK_HZ+1):2;
 reg[HOLD_W-1:0] n_hold,a_hold;
 reg[CHORD_W-1:0] chord;reg[4:0] seconds;reg[CYCLE_W-1:0] cycles;
 reg chord_used,chord_fired,n_long,a_long;
 wire [5:0] interval=(period_select==0)?2:(period_select==1)?5:(period_select==2)?10:30;
 function[6:0] offset_to_percent;input signed[8:0] offset;reg signed[8:0] shifted;begin
  shifted=offset+9'sd100;
  if(offset < -9'sd100)offset_to_percent=0;
  else if(offset > 9'sd100)offset_to_percent=100;
  else offset_to_percent=shifted[7:1];
 end endfunction
 task increase;input inc;reg[6:0] next_pct;reg[1:0] next_scale;begin
 case(field)
  0:if(HANDBOOK_PROFILE)begin
     next_pct=inc?((brightness_pct<95)?brightness_pct+7'd5:7'd100):((brightness_pct>5)?brightness_pct-7'd5:7'd0);
     brightness_pct<=next_pct;brightness<=$signed({1'b0,next_pct,1'b0})-9'sd100;brightness_raw<=0;
    end else if(inc)begin if(brightness<120)brightness<=brightness+8;else brightness<=127;end
    else begin if(brightness>-120)brightness<=brightness-8;else brightness<=-128;end
  1:if(HANDBOOK_PROFILE)begin
     if(inc)contrast<=contrast<64?64:contrast>247?255:contrast+8;
     else contrast<=contrast<=72?64:contrast-8;
    end else if(inc)begin if(contrast<239)contrast<=contrast+16;else contrast<=255;end
    else begin if(contrast>16)contrast<=contrast-16;else contrast<=0;end
  2:bilinear<=!bilinear;
  3:begin
     next_scale=HANDBOOK_PROFILE?(inc?scale_select+1'b1:scale_select-1'b1):(!fit?2'd1:2'd0);
     scale_select<=next_scale;fit<=next_scale==1;
    end
  4:fade_enabled<=!fade_enabled;
  5:if(HANDBOOK_PROFILE)begin
     if(inc)volume<=volume<90?volume+10:100;
     else volume<=volume>10?volume-10:0;
    end else if(inc)begin if(volume<95)volume<=volume+5;else volume<=100;end
    else begin if(volume>5)volume<=volume-5;else volume<=0;end
  6:period_select<=inc?period_select+1'b1:period_select-1'b1;
  7:osd_alpha<=inc?((osd_alpha<239)?osd_alpha+16:255):((osd_alpha>16)?osd_alpha-16:0);
 endcase
 end endtask
 wire controls_power_reset_n=RETAIN_CONFIG?config_rst_n:rst_n;
 always @(posedge clk or negedge controls_power_reset_n)begin
  if(!controls_power_reset_n)begin previous<=0;n_hold<=0;a_hold<=0;chord<=0;chord_used<=0;chord_fired<=0;n_long<=0;a_long<=0;
   next_request<=0;auto_enabled<=DEFAULT_AUTO;recover_request<=0;reply_valid<=0;reply_code<=0;
   brightness<=HANDBOOK_PROFILE?60:0;brightness_pct<=HANDBOOK_PROFILE?80:50;brightness_raw<=!HANDBOOK_PROFILE;
   contrast<=128;osd_alpha<=160;bilinear<=0;fit<=!HANDBOOK_PROFILE;scale_select<=HANDBOOK_PROFILE?0:1;fade_enabled<=1;
   volume<=HANDBOOK_PROFILE?70:80;period_select<=1;period_previous<=1;menu<=0;field<=0;auto_tick<=0;cycles<=0;seconds<=0;reply_value<=0;end
  else if(!rst_n)begin
   // Warm SYS reset clears transactions and key history; configuration remains
   // held until an explicit write. FPGA configuration/power-on reloads defaults.
   previous<=0;n_hold<=0;a_hold<=0;chord<=0;chord_used<=0;chord_fired<=0;n_long<=0;a_long<=0;
   next_request<=0;recover_request<=0;reply_valid<=0;reply_code<=0;reply_value<=0;
   period_previous<=period_select;menu<=0;field<=0;auto_tick<=0;cycles<=0;seconds<=0;
  end
  else begin
   previous<=levels;period_previous<=period_select;next_request<=0;recover_request<=0;reply_valid<=0;auto_tick<=0;
   if(levels[0] && levels[1])begin
    chord_used<=1;
    if(chord<2*CLK_HZ)chord<=chord+1'b1;
    else if(!chord_fired)begin menu<=!menu;chord_fired<=1;n_long<=1;a_long<=1;end
   end else chord<=0;
   if(levels[0])begin
    if(n_hold<CLK_HZ)n_hold<=n_hold+1'b1;
    else if(menu && !levels[1] && !n_long)begin field<=field+1'b1;n_long<=1;end
   end
   if(levels[1])begin
    if(a_hold<CLK_HZ)a_hold<=a_hold+1'b1;
    else if(menu && !levels[0] && !a_long)begin menu<=0;a_long<=1;end
   end
   if(previous[0] && !levels[0])begin
    n_hold<=0;
    if(!n_long && !chord_used)begin
     if(safety || !cached || (SYSTEM_SAFE_ENABLE && system_safe))recover_request<=1;
     else if(menu)increase(1);
     else if(!transition_busy)next_request<=1;
    end n_long<=0;
   end
   if(previous[1] && !levels[1])begin
    a_hold<=0;if(!a_long && !chord_used)begin
     if(menu)increase(0);else auto_enabled<=!auto_enabled;
    end a_long<=0;
   end
   if(levels[1:0]==0 && previous[1:0]==0)begin chord_used<=0;chord_fired<=0;end
   if(!auto_enabled || !cached || safety || menu || frame_commit || period_select!=period_previous)begin cycles<=0;seconds<=0;end
   else if(cycles==CLK_HZ-1)begin
    cycles<=0;
    if(seconds==interval-1)begin seconds<=0;if(!transition_busy)auto_tick<=1;end
    else seconds<=seconds+1'b1;
   end else cycles<=cycles+1'b1;
   if(command_valid)begin
    reply_valid<=1;reply_code<=0;reply_value<=0;
    if(command_query)begin
     if(command_target==65 && opcode==OP_BRIGHT)reply_value<=brightness;
     else if(command_target==65 && opcode==OP_CONTRAST)reply_value<=contrast;
     else if(command_target==65 && opcode==OP_ALPHA)reply_value<=osd_alpha;
     else if(command_target==65 && opcode==OP_SCALER)reply_value<=bilinear;
     else if(command_target==65 && opcode==OP_SCALE)reply_value<=fit;
     else if(command_target==65 && opcode==OP_FADE)reply_value<=fade_enabled;
     else if(command_target==67 && opcode==OP_VOL)reply_value<=volume;
     else if(command_target==67 && opcode==OP_PERIOD)reply_value<=interval;
     else if(command_target==67 && opcode==OP_AUTO)reply_value<=auto_enabled;
     else if(command_target==65 && opcode==OP_BRTPC)reply_value<=brightness_pct;
     else if(command_target==65 && opcode==OP_SCALESEL)reply_value<=scale_select;
     else if(command_target==67 && opcode==OP_MENU)reply_value<=menu;
     else if(command_target==67 && opcode==OP_FIELD)reply_value<=field;
     else reply_code<=3;
    end
    else case(opcode)
     OP_BRIGHT:if(command_target==8'd65 && value_bright_ok)begin
      brightness<=command_value;brightness_pct<=offset_to_percent(command_value[8:0]);brightness_raw<=1;
     end else reply_code<=3;
     OP_CONTRAST:if(command_target==8'd65 && value_byte_ok)contrast<=command_value;else reply_code<=3;
     OP_ALPHA:if(command_target==8'd65 && value_byte_ok)osd_alpha<=command_value;else reply_code<=3;
     OP_SCALER:if(command_target==8'd65 && value_bit_ok)bilinear<=command_value;else reply_code<=3;
     OP_SCALE:if(command_target==8'd65 && value_bit_ok)begin fit<=command_value;scale_select<=command_value[1:0];end else reply_code<=3;
     OP_FADE:if(command_target==8'd65 && value_bit_ok)fade_enabled<=command_value;else reply_code<=3;
     OP_VOL:if(command_target==8'd67 && value_volume_ok)volume<=command_value;else reply_code<=3;
     OP_PERIOD:if(command_target==8'd67)begin case(command_value)
      2:period_select<=0;5:period_select<=1;10:period_select<=2;30:period_select<=3;default:reply_code<=3;
     endcase end else reply_code<=3;
     OP_AUTO:if(command_target==8'd67 && value_bit_ok)auto_enabled<=command_value;else reply_code<=3;
     OP_NEXT:if(command_target==8'd67 && command_value==1)begin
      if(!transition_busy && cached && !safety)next_request<=1;else reply_code<=4;
     end else reply_code<=3;
     OP_RECOVER:if(command_target==8'd67 && command_value==1)recover_request<=1;else reply_code<=3;
     OP_BRTPC:if(command_target==8'd65 && value_volume_ok)begin
      brightness_pct<=command_value[6:0];brightness<=$signed({1'b0,command_value[6:0],1'b0})-9'sd100;brightness_raw<=0;
     end else reply_code<=3;
     OP_SCALESEL:if(command_target==8'd65 && !(|command_value[31:2]))begin
      scale_select<=command_value[1:0];fit<=command_value[1:0]==1;
     end else reply_code<=3;
     OP_MENU:if(command_target==8'd67 && value_bit_ok)menu<=command_value[0];else reply_code<=3;
     OP_FIELD:if(command_target==8'd67 && !(|command_value[31:3]))field<=command_value[2:0];else reply_code<=3;
     default:reply_code<=3;
    endcase
   end
  end
 end
endmodule
