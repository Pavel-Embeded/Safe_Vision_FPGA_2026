// Normal buttons are decoded on release, so a chord cannot leak a next/auto.
// Emergency is never gated by menu or UART. Configuration has one driver.
module v3_user_controls_reference #(parameter integer CLK_HZ=100000000,DEBOUNCE=2000000)(
 input wire clk,rst_n,next_async,auto_async,emergency_async,
 input wire command_valid,input wire [7:0] command_target,
 input wire [95:0] command_name,input wire signed [31:0] command_value,input wire command_query,
 input wire cached,transition_busy,frame_commit,
 output reg next_request,output reg auto_enabled,output wire safety,
 output reg recover_request,output reg reply_valid,output reg [7:0] reply_code,
 output reg signed [31:0] reply_value,
 output reg signed [8:0] brightness,output reg [7:0] contrast,osd_alpha,
 output reg bilinear,fit,fade_enabled,output reg [6:0] volume,
 output reg [1:0] period_select,output reg menu,
 output reg [2:0] field,output reg auto_tick);
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
 task increase;input inc;begin
 case(field)
  0:if(inc)begin if(brightness<120)brightness<=brightness+8;else brightness<=127;end
    else begin if(brightness>-120)brightness<=brightness-8;else brightness<=-128;end
  1:if(inc)begin if(contrast<239)contrast<=contrast+16;else contrast<=255;end
    else begin if(contrast>16)contrast<=contrast-16;else contrast<=0;end
  2:bilinear<=!bilinear;
  3:fit<=!fit;
  4:fade_enabled<=!fade_enabled;
  5:if(inc)begin if(volume<95)volume<=volume+5;else volume<=100;end
    else begin if(volume>5)volume<=volume-5;else volume<=0;end
  6:period_select<=inc?period_select+1'b1:period_select-1'b1;
  7:osd_alpha<=inc?((osd_alpha<239)?osd_alpha+16:255):((osd_alpha>16)?osd_alpha-16:0);
 endcase
 end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin previous<=0;n_hold<=0;a_hold<=0;chord<=0;chord_used<=0;chord_fired<=0;n_long<=0;a_long<=0;
   next_request<=0;auto_enabled<=0;recover_request<=0;reply_valid<=0;reply_code<=0;
   brightness<=0;contrast<=128;osd_alpha<=160;bilinear<=0;fit<=1;fade_enabled<=1;
   volume<=80;period_select<=1;period_previous<=1;menu<=0;field<=0;auto_tick<=0;cycles<=0;seconds<=0;reply_value<=0;end
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
     if(safety || !cached)recover_request<=1;
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
     if(command_target==65 && command_name=="BRIGHT")reply_value<=brightness;
     else if(command_target==65 && command_name=="CONTRAST")reply_value<=contrast;
     else if(command_target==65 && command_name=="ALPHA")reply_value<=osd_alpha;
     else if(command_target==65 && command_name=="SCALER")reply_value<=bilinear;
     else if(command_target==65 && command_name=="SCALE")reply_value<=fit;
     else if(command_target==65 && command_name=="FADE")reply_value<=fade_enabled;
     else if(command_target==67 && command_name=="VOL")reply_value<=volume;
     else if(command_target==67 && command_name=="PERIOD")reply_value<=interval;
     else if(command_target==67 && command_name=="AUTO")reply_value<=auto_enabled;
     else reply_code<=3;
    end
    else if(command_target==65 && command_name=="BRIGHT" && command_value>=-128 && command_value<=127)brightness<=command_value;
    else if(command_target==65 && command_name=="CONTRAST" && command_value>=0 && command_value<=255)contrast<=command_value;
    else if(command_target==65 && command_name=="ALPHA" && command_value>=0 && command_value<=255)osd_alpha<=command_value;
    else if(command_target==65 && command_name=="SCALER" && command_value>=0 && command_value<=1)bilinear<=command_value;
    else if(command_target==65 && command_name=="SCALE" && command_value>=0 && command_value<=1)fit<=command_value;
    else if(command_target==65 && command_name=="FADE" && command_value>=0 && command_value<=1)fade_enabled<=command_value;
    else if(command_target==67 && command_name=="VOL" && command_value>=0 && command_value<=100)volume<=command_value;
    else if(command_target==67 && command_name=="PERIOD")begin
     case(command_value)2:period_select<=0;5:period_select<=1;10:period_select<=2;30:period_select<=3;default:reply_code<=3;endcase
    end else if(command_target==67 && command_name=="AUTO" && command_value>=0 && command_value<=1)auto_enabled<=command_value;
    else if(command_target==67 && command_name=="NEXT" && command_value==1)begin if(!transition_busy && cached && !safety)next_request<=1;else reply_code<=4;end
    else if(command_target==67 && command_name=="RECOVER" && command_value==1)recover_request<=1;
    else reply_code<=3;
   end
  end
 end
endmodule
