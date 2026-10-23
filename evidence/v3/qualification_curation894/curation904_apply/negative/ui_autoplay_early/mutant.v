// Decode one-hot on the same command capture edge. Legal and invalid opcodes
// retain all response/configuration cycles; no additional pipeline stage.
// Normal buttons are decoded on release, so a chord cannot leak a next/auto.
// Emergency is never gated by menu or UART. Configuration has one driver.
module v3_user_controls #(parameter integer UI_TIMEBASE=0,CLK_HZ=100000000,DEBOUNCE=2000000,BOARD_CATALOG=0,SYSTEM_SAFE_ENABLE=0,
 HANDBOOK_PROFILE=0,DEFAULT_AUTO=0,RETAIN_CONFIG=0,COMMAND_PIPELINE=HANDBOOK_PROFILE)(
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
 wire value_bright_ok=(~|command_value[31:7]) || (&command_value[31:7]);
 wire value_byte_ok=~|command_value[31:8];
 wire value_bit_ok=~|command_value[31:1];
 wire value_volume_ok=(~|command_value[31:7]) && command_value[6:0]<=7'd100;
 // Decode A/C target on the original command-pipeline capture edge:
 // R(target==A/C)=(R(target)==A/C), for all256 target encodings.
 // Pipeline the finite decoded command and validated nine-bit argument.
 // Values outside signed9 bits become an invalid sentinel, never a wrapped
 // legal command. Four range predicates retain the full32-bit input checks.
 // Adds one SYS edge in handbook mode; legacy callers retain exact latency.
 function[6:0] offset_to_percent;input signed[8:0] offset;reg signed[8:0] shifted;begin
  shifted=offset+9'sd100;
  if(offset < -9'sd100)offset_to_percent=0;
  else if(offset > 9'sd100)offset_to_percent=100;
  else offset_to_percent=shifted[7:1];
 end endfunction
 wire[3:0] opcode_in=BOARD_CATALOG?decode_catalog(catalog_id):decode_name(command_name);
 wire[3:0] opcode;wire[15:0] operation;wire command_valid_eff,command_query_eff;
 wire alpha_write_eff;
 // Register target-qualified one-hot operations on the original capture edge.
 wire[15:0] qualified_operation=(16'h1<<opcode_in)&(({16{command_target==8'd65}}&16'h183f)|({16{command_target==8'd67}}&16'h67c0));
 wire[6:0] bright_percent_eff;wire signed[8:0] percent_offset_eff;
 wire[7:0] command_target_eff;wire signed[31:0] command_value_eff;
 wire target_a_eff,target_c_eff;
 wire value_bright_qualified,value_byte_qualified,value_bit_qualified,value_volume_qualified;
 generate if(COMMAND_PIPELINE)begin:command_pipeline
  reg valid_q,query_q;reg[7:0] target_q;reg[3:0] opcode_q;
  reg[15:0] operation_q;
  reg alpha_write_q;
  // ALPHA is fully validated at the existing capture edge. The response
  // decoder remains unchanged, while the configuration data mux receives
  // one registered enable instead of the entire command-priority network.
  always @(posedge clk or negedge rst_n)
   if(!rst_n)alpha_write_q<=0;
   else alpha_write_q<=command_valid&&!command_query&&qualified_operation[OP_ALPHA]&&value_byte_ok;
  assign alpha_write_eff=alpha_write_q;
  reg target_a_q,target_c_q;
  reg[8:0] argument_q;
  always@(posedge clk or negedge rst_n)begin
   if(!rst_n)begin valid_q<=0;query_q<=0;target_q<=0;target_a_q<=0;target_c_q<=0;opcode_q<=15;operation_q<=0;argument_q<=0;
end
   else begin valid_q<=command_valid;query_q<=command_query;target_q<=command_target;opcode_q<=opcode_in;operation_q<=qualified_operation;
    target_a_q<=command_target==8'd65;target_c_q<=command_target==8'd67;
    argument_q<=command_value[31:9]=={23{command_value[8]}}?command_value[8:0]:9'h100;

   end
  end
  assign opcode=opcode_q;assign operation=operation_q;assign bright_percent_eff=offset_to_percent(argument_q);assign percent_offset_eff=$signed({1'b0,argument_q[6:0],1'b0})-9'sd100;assign command_valid_eff=valid_q;assign command_query_eff=query_q;
  assign target_a_eff=target_a_q;assign target_c_eff=target_c_q;
  assign command_target_eff=target_q;assign command_value_eff={{23{argument_q[8]}},argument_q};
  // Every accepted control value is in-128..255. The clipped9-bit
  // argument uses-256 for ALL out-of-domain values; that sentinel is
  // invalid for every operation. Derive the four exact validity classes
  // after capture instead of registering redundant32-bit predicates.
  assign value_bright_qualified=(argument_q[8]==argument_q[7]);assign value_byte_qualified=!argument_q[8];
  assign value_bit_qualified=!(|argument_q[8:1]);assign value_volume_qualified=!argument_q[8]&&(argument_q[7:0]<=8'd100);
 end else begin:command_direct
  assign alpha_write_eff=1'b0;
  assign opcode=opcode_in;assign operation=qualified_operation;assign bright_percent_eff=offset_to_percent(command_value[8:0]);assign percent_offset_eff=$signed({1'b0,command_value[6:0],1'b0})-9'sd100;assign command_valid_eff=command_valid;assign command_query_eff=command_query;
  assign target_a_eff=command_target==8'd65;assign target_c_eff=command_target==8'd67;
  assign command_target_eff=command_target;assign command_value_eff=command_value;
  assign value_bright_qualified=value_bright_ok;assign value_byte_qualified=value_byte_ok;
  assign value_bit_qualified=value_bit_ok;assign value_volume_qualified=value_volume_ok;
 end endgenerate

 // Exact two's-complement tests for all 2^32 input bit patterns. Command
 // decoding is independent of value validity, so one command's rejected
 // value cannot build a priority path to another command's enable.
 // Board-only shared millisecond enable. Every physical clock continues.
 // Exact-cycle callers and accelerated/nonintegral debounce profiles keepDIV1.
 localparam integer UI_DIV=UI_TIMEBASE&&CLK_HZ>=1000&&CLK_HZ%1000==0&&DEBOUNCE>=CLK_HZ/1000&&DEBOUNCE%(CLK_HZ/1000)==0?CLK_HZ/1000:1;
 localparam integer UI_SECOND=CLK_HZ/UI_DIV;
 localparam integer HOLD_LIMIT=UI_DIV==1?CLK_HZ:UI_SECOND+1;
 localparam integer CHORD_LIMIT=UI_DIV==1?2*CLK_HZ:2*UI_SECOND+1;
 localparam integer UI_DEBOUNCE=UI_DIV==1?DEBOUNCE:DEBOUNCE/UI_DIV+1;
 localparam integer UI_PHASE_W=UI_DIV>1?$clog2(UI_DIV):1;
 wire controls_power_reset_n=RETAIN_CONFIG?config_rst_n:rst_n;
 reg[UI_PHASE_W-1:0] ui_phase;reg auto_started;
 wire ui_tick=UI_DIV==1||ui_phase==UI_DIV-1;
 always@(posedge clk or negedge controls_power_reset_n)
  if(!controls_power_reset_n)ui_phase<=0;
  else if(!rst_n||ui_tick)ui_phase<=0;else ui_phase<=ui_phase+1'b1;
 wire [2:0] levels,press;
 key_debounce #(.USE_TICK(UI_DIV!=1),.KEYS(3),.DEB_N(UI_DEBOUNCE),.RESET_LEVEL(0)) buttons(
 .tick(ui_tick),.clk(clk),.rst_n(rst_n),.key_async({!emergency_async,!auto_async,!next_async}),
 .evt_clear(1'b1),.key_level(levels),.press_vec(press),.press_any(),.evt_key(),.evt_pending());
 assign safety=levels[2];
 reg [2:0] previous;reg [1:0] period_previous;
 localparam integer HOLD_W=(HOLD_LIMIT>1)?$clog2(HOLD_LIMIT+1):1;
 localparam integer CYCLE_W=(UI_SECOND>1)?$clog2(UI_SECOND):1;
 localparam integer CHORD_W=(CHORD_LIMIT>1)?$clog2(CHORD_LIMIT+1):2;
 reg[HOLD_W-1:0] n_hold,a_hold;
 reg[CHORD_W-1:0] chord;reg[4:0] seconds_raw;reg[CYCLE_W-1:0] cycles_raw;
 reg timer_clear_q;
 wire[4:0] seconds=timer_clear_q?0:seconds_raw;
 wire[CYCLE_W-1:0] cycles=timer_clear_q?0:cycles_raw;
 wire timer_clear=!auto_enabled || !cached || safety || menu || frame_commit || period_select!=period_previous;
 (* use_ripple=1 *) wire[HOLD_W-1:0] next_n_hold=n_hold+1'b1,next_a_hold=a_hold+1'b1;
 (* use_ripple=1 *) wire[CHORD_W-1:0] next_chord=chord+1'b1;
 reg chord_used,chord_fired,n_long,a_long;
 wire [5:0] interval=(period_select==0)?2:(period_select==1)?5:(period_select==2)?10:30;
 (* use_ripple=1 *) wire signed[8:0] button_bright_up=$signed({1'b0,brightness_pct,1'b0})-9'sd90;
 (* use_ripple=1 *) wire signed[8:0] button_bright_down=$signed({1'b0,brightness_pct,1'b0})-9'sd110;
 task increase;input inc;reg[6:0] next_pct;reg[1:0] next_scale;begin
 case(field)
  0:if(HANDBOOK_PROFILE)begin
     next_pct=inc?((brightness_pct<95)?brightness_pct+7'd5:7'd100):((brightness_pct>5)?brightness_pct-7'd5:7'd0);
     brightness_pct<=next_pct;
     // 2*(pct+5)-100 = 2*pct-90; likewise decrement uses -110.
     // Compute arithmetic before the saturation mux, avoiding two serial
     // carry paths from the released button to the brightness register.
     brightness<=inc?((brightness_pct<95)?button_bright_up:9'sd100):
                     ((brightness_pct>5)?button_bright_down:-9'sd100);
     brightness_raw<=0;
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
 // Mutually exclusive captured operations permit a balanced masked-OR query.
 wire query_known=|(operation&16'h79ff);
 wire[31:0] query_word=
  ({32{operation[OP_BRIGHT]}}&{{23{brightness[8]}},brightness}) |
  ({32{operation[OP_CONTRAST]}}&{24'd0,contrast}) |
  ({32{operation[OP_ALPHA]}}&{24'd0,osd_alpha}) |
  ({32{operation[OP_SCALER]}}&{31'd0,bilinear}) |
  ({32{operation[OP_SCALE]}}&{31'd0,fit}) |
  ({32{operation[OP_FADE]}}&{31'd0,fade_enabled}) |
  ({32{operation[OP_VOL]}}&{25'd0,volume}) |
  ({32{operation[OP_PERIOD]}}&{26'd0,interval}) |
  ({32{operation[OP_AUTO]}}&{31'd0,auto_enabled}) |
  ({32{operation[OP_BRTPC]}}&{25'd0,brightness_pct}) |
  ({32{operation[OP_SCALESEL]}}&{30'd0,scale_select}) |
  ({32{operation[OP_MENU]}}&{31'd0,menu}) |
  ({32{operation[OP_FIELD]}}&{29'd0,field});
 always @(posedge clk or negedge controls_power_reset_n)begin
  if(!controls_power_reset_n)begin previous<=0;n_hold<=0;a_hold<=0;chord<=0;chord_used<=0;chord_fired<=0;n_long<=0;a_long<=0;
   next_request<=0;auto_enabled<=DEFAULT_AUTO;recover_request<=0;reply_valid<=0;reply_code<=0;
   brightness<=HANDBOOK_PROFILE?60:0;brightness_pct<=HANDBOOK_PROFILE?80:50;brightness_raw<=!HANDBOOK_PROFILE;
   contrast<=128;osd_alpha<=160;bilinear<=0;fit<=!HANDBOOK_PROFILE;scale_select<=HANDBOOK_PROFILE?0:1;fade_enabled<=1;
   volume<=HANDBOOK_PROFILE?70:80;period_select<=1;period_previous<=1;menu<=0;field<=0;auto_tick<=0;cycles_raw<=0;seconds_raw<=0;timer_clear_q<=1;auto_started<=0;reply_value<=0;end
  else if(!rst_n)begin
   // Warm SYS reset clears transactions and key history; configuration remains
   // held until an explicit write. FPGA configuration/power-on reloads defaults.
   previous<=0;n_hold<=0;a_hold<=0;chord<=0;chord_used<=0;chord_fired<=0;n_long<=0;a_long<=0;
   next_request<=0;recover_request<=0;reply_valid<=0;reply_code<=0;reply_value<=0;
   period_previous<=period_select;menu<=0;field<=0;auto_tick<=0;cycles_raw<=0;seconds_raw<=0;timer_clear_q<=1;auto_started<=0;
  end
  else begin
   previous<=levels;period_previous<=period_select;next_request<=0;recover_request<=0;reply_valid<=0;auto_tick<=0;
   if(levels[0] && levels[1])begin
    chord_used<=1;
    if(chord<CHORD_LIMIT)begin if(ui_tick)chord<=next_chord;end
    else if(!chord_fired)begin menu<=!menu;chord_fired<=1;n_long<=1;a_long<=1;end
   end else chord<=0;
   if(levels[0])begin
    if(n_hold<HOLD_LIMIT)begin if(ui_tick)n_hold<=next_n_hold;end
    else if(menu && !levels[1] && !n_long)begin field<=field+1'b1;n_long<=1;end
   end
   if(levels[1])begin
    if(a_hold<HOLD_LIMIT)begin if(ui_tick)a_hold<=next_a_hold;end
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
   // Encode the published zero state on the original edge. Late cache/
   // commit decisions only feed one FF; timer values and auto_tick remain exact.
   timer_clear_q<=timer_clear;
   if(UI_DIV==1)begin
   if(cycles==CLK_HZ-1)begin
    cycles_raw<=0;
    if(seconds==interval-1)begin seconds_raw<=0;if(!timer_clear && !transition_busy)auto_tick<=1;end
    else seconds_raw<=seconds+1'b1;
   end else begin cycles_raw<=cycles+1'b1;seconds_raw<=seconds;end
   end else if(timer_clear_q)begin cycles_raw<=0;seconds_raw<=0;auto_started<=0;end
   else if(ui_tick)begin
    // Start at the first common tick after clear. The first period is never
    // shortened; thereafter the integer2/5/10/30-second interval is exact.
    if(!auto_started)begin auto_started<=1;cycles_raw<=0;seconds_raw<=0;end
    else if(cycles_raw==UI_SECOND-2)begin
     cycles_raw<=0;
     if(seconds_raw==interval-1)begin seconds_raw<=0;if(!timer_clear&&!transition_busy)auto_tick<=1;end
     else seconds_raw<=seconds_raw+1'b1;
    end else cycles_raw<=cycles_raw+1'b1;
   end
   if(command_valid_eff)begin
    reply_valid<=1;reply_code<=0;reply_value<=0;
    if(command_query_eff)begin
     reply_value<=query_word;
     if(!query_known)reply_code<=3;
    end
    else case(1'b1) // synthesis parallel_case
     operation[OP_BRIGHT]:if(value_bright_qualified)begin
      brightness<=command_value_eff;brightness_pct<=bright_percent_eff;brightness_raw<=1;
     end else reply_code<=3;
     operation[OP_CONTRAST]:if(value_byte_qualified)contrast<=command_value_eff;else reply_code<=3;
     operation[OP_ALPHA]:if(value_byte_qualified)begin if(!COMMAND_PIPELINE)osd_alpha<=command_value_eff;end else reply_code<=3;
     operation[OP_SCALER]:if(value_bit_qualified)bilinear<=command_value_eff;else reply_code<=3;
     operation[OP_SCALE]:if(value_bit_qualified)begin fit<=command_value_eff;scale_select<=command_value_eff[1:0];end else reply_code<=3;
     operation[OP_FADE]:if(value_bit_qualified)fade_enabled<=command_value_eff;else reply_code<=3;
     operation[OP_VOL]:if(value_volume_qualified)volume<=command_value_eff;else reply_code<=3;
     operation[OP_PERIOD]:begin case(command_value_eff)
      2:period_select<=0;5:period_select<=1;10:period_select<=2;30:period_select<=3;default:reply_code<=3;
     endcase end
     operation[OP_AUTO]:if(value_bit_qualified)auto_enabled<=command_value_eff;else reply_code<=3;
     operation[OP_NEXT]:if(command_value_eff==1)begin
      if(!transition_busy && cached && !safety)next_request<=1;else reply_code<=4;
     end else reply_code<=3;
     operation[OP_RECOVER]:if(command_value_eff==1)recover_request<=1;else reply_code<=3;
     operation[OP_BRTPC]:if(value_volume_qualified)begin
      brightness_pct<=command_value_eff[6:0];brightness<=percent_offset_eff;brightness_raw<=0;
     end else reply_code<=3;
     operation[OP_SCALESEL]:if(!(|command_value_eff[31:2]))begin
      scale_select<=command_value_eff[1:0];fit<=command_value_eff[1:0]==1;
     end else reply_code<=3;
     operation[OP_MENU]:if(value_bit_qualified)menu<=command_value_eff[0];else reply_code<=3;
     operation[OP_FIELD]:if(!(|command_value_eff[31:3]))field<=command_value_eff[2:0];else reply_code<=3;
     default:reply_code<=3;
    endcase
   end
   // Last assignment preserves UART-over-button priority on the same edge.
   if(COMMAND_PIPELINE&&alpha_write_eff)osd_alpha<=command_value_eff[7:0];
  end
 end
endmodule
