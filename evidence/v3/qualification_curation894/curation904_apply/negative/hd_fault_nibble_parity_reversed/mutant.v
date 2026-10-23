// HEX payload nibble and type cross the existing override1 edge together.
// ASCII expansion moves after that register; all four-pixel output tags stay exact.
// Fixed four pixel clocks from raw scan to every layer. Text and glyph ROMs
// each have two synchronous read ports shared by normal/SAFE presentation.
// Compact font is lossless for the checked-in font: rows 0/15 and codes >=128
// are blank; rows 1/2,...,13/14 are identical. Both ROMs fit one RAM9K tile.
module v3_status_layers #(
 parameter integer HD=0,HANDBOOK_PROFILE=0,USER_FEATURES=0,FLEX_SPECTRUM=0,VOLUME_COLUMNS=0,VOLUME_SETTING=0,PIXEL_HZ=HD?74250000:25175000,PIPE_LATENCY=21,
 parameter integer RASTER_PREDECODE=0,
 parameter FONT_FILE="../../../assets/fonts/font8x16.mem",
 parameter COMPACT_FONT_FILE="../../assets/fonts/font8x16_compact.mem",
 parameter USER_TEXT_FILE="v3_four_features_text.mem",
 parameter TEXT_FILE="../../assets/fonts/v3_status_text.mem"
)(
 input wire pixel_clk,pixel_rst_n,
 input wire[31:0] uptime_bcd,input wire wave_pcm_valid,input wire[23:0] wave_pcm_left,
 input wire[11:0] raw_x,raw_y,input wire raw_de,frame_start,
 input wire[(HANDBOOK_PROFILE?99:96)-1:0] cfg_data,input wire[3:0] cache_valid,
 input wire[31:0] underflows,input wire[1:0] active_slot,
 input wire[7:0] generation,input wire busy,safety_active,
 output wire[15:0] osd_rgb565,emergency_rgb565,hud_rgb565,safe_rgb565,
 output wire[7:0] osd_alpha,emergency_alpha,hud_alpha
);
 localparam integer DESCRIPTOR_TEXT=USER_FEATURES&&HANDBOOK_PROFILE;
 localparam integer WIDTH=HD?1280:640,HEIGHT=HD?720:480;
 localparam integer SECOND_TICKS=HANDBOOK_PROFILE?PIXEL_HZ/2:PIXEL_HZ;
 localparam integer SECOND_W=SECOND_TICKS>1?$clog2(SECOND_TICKS):1;
 wire[98:0] cfg_extended=cfg_data;
 wire raw_brightness=HANDBOOK_PROFILE?cfg_extended[98]:1'b1;
 wire[1:0] scale_select=HANDBOOK_PROFILE?cfg_extended[97:96]:{1'b0,cfg_data[69]};
 reg[SECOND_W-1:0] second_count;reg[7:0] frame_count,fps;
 reg[5:0] blink_count;reg blink;
 wire[9:0] measured_frames={2'b0,frame_count}+(frame_start?10'd1:10'd0);
 wire[9:0] measured_fps=HANDBOOK_PROFILE?{measured_frames[8:0],1'b0}:measured_frames;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin second_count<=0;frame_count<=0;fps<=0;blink_count<=0;blink<=1;end
  else begin
   if(second_count==SECOND_TICKS-1)begin second_count<=0;fps<=measured_fps>255?8'hff:measured_fps[7:0];frame_count<=0;end
   else begin second_count<=second_count+1'b1;if(frame_start&&frame_count!=255)frame_count<=frame_count+1'b1;end
   if(frame_start)begin if(blink_count==29)begin blink_count<=0;blink<=~blink;end else blink_count<=blink_count+1'b1;end
  end
 end
 function[7:0] hexchar;input[3:0] n;begin hexchar=n<10?8'd48+n:8'd55+n;end endfunction
 // One iterative double-dabble converter, six values in sixty clocks. No
 // combinational division/modulo. The converter is outside the pixel path.
 // cfg/slot/generation commit at vblank. The first visible glyph is thousands
 // of clocks later. All text ROM/glyph pipeline tags retain their four clocks.
 reg[2:0] decimal_select;reg[9:0] decimal_digits[0:6];reg[8:0] decimal_value;
 wire signed[8:0] brightness=HANDBOOK_PROFILE?{cfg_data[94],cfg_data[94:87]}:cfg_data[95:87];
 wire[8:0] percent_shifted=brightness+9'd100;
 wire[8:0] magnitude=brightness[8]?-brightness:brightness;
 reg[8:0] decimal_binary;reg[11:0] decimal_work;reg[3:0] decimal_left;
 wire[3:0] dh=decimal_work[11:8]>=5?decimal_work[11:8]+4'd3:decimal_work[11:8];
 wire[3:0] dt=decimal_work[7:4]>=5?decimal_work[7:4]+4'd3:decimal_work[7:4];
 wire[3:0] do_=decimal_work[3:0]>=5?decimal_work[3:0]+4'd3:decimal_work[3:0];
 wire[11:0] decimal_next={dh[2:0],dt,do_,decimal_binary[8]};
 always @*begin
  case(decimal_select)0:decimal_value={1'b0,generation};1:decimal_value={1'b0,fps};
   2:decimal_value=raw_brightness?magnitude:{2'd0,percent_shifted[7:1]};3:decimal_value={1'b0,cfg_data[86:79]};
   4:decimal_value={2'b0,cfg_data[67:61]};5:decimal_value={1'b0,cfg_data[78:71]};default:decimal_value={1'b0,cfg_data[7:0]};endcase
 end
 integer d;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin decimal_select<=0;decimal_binary<=0;decimal_work<=0;decimal_left<=0;
   for(d=0;d<7;d=d+1)decimal_digits[d]<=0;end
  else if(decimal_left==0)begin decimal_binary<=decimal_value;decimal_work<=0;decimal_left<=9;end
  else begin decimal_binary<={decimal_binary[7:0],1'b0};decimal_work<=decimal_next;
   decimal_left<=decimal_left-1'b1;
   if(decimal_left==1)begin decimal_digits[decimal_select]<=decimal_next[9:0];
    if(decimal_select==(HANDBOOK_PROFILE?6:5))decimal_select<=0;else decimal_select<=decimal_select+1'b1;end
  end
 end
 function[7:0] decimal_char;input[9:0] bcd;input[1:0] place;
  begin case(place)2:decimal_char=8'd48+{2'd0,bcd[9:8]};1:decimal_char=8'd48+bcd[7:4];default:decimal_char=8'd48+bcd[3:0];endcase end
 endfunction
 wire[6:0] energy=cfg_data[54:48]>100?7'd100:cfg_data[54:48];
 // Origin x=8 is byte aligned: column bits pass through, index is x/8-1.
 wire[7:0] index=raw_x[10:3]-8'd1;
 // These two fields are selected only inside their8-character HEX windows.
 // Subtraction modulo8 is exact there; isolate the actual32-bit word first.
 wire[2:0] underflow_nibble=3'd0-index[2:0];
 wire[2:0] address_nibble=3'd2-index[2:0];
 wire[31:0] displayed_address=cfg_data[39:8];

 // Fixed-raster profile only: predict the coordinate which the timing core
 // publishes after THIS edge, then decode its row bands in parallel. The
 // character formatter still uses live cfg/index/decimal values at the next
 // edge, exactly as before. General coordinate clients retain direct decode.
 localparam integer RASTER_HT=HD?1650:800,RASTER_VT=HD?750:525;
 wire[6:0] band;wire[3:0] menu_row_pre;wire[11:0] menu_origin_pre;wire menu_gap_pre;
 generate if(RASTER_PREDECODE)begin:fixed_raster_bands
  // At line end y advances by one. Shift constant comparison thresholds
  // by one instead of placing a wide y+1 / coordinate mux in front of them.
  // Band0 is false on reset row0; every later row is prepared before x=0.
  wire row_end=raw_x==RASTER_HT-1;
  wire[3:0] next_menu=raw_y>=239?8:raw_y>=219?7:raw_y>=199?6:raw_y>=179?5:raw_y>=159?4:raw_y>=139?3:raw_y>=119?2:raw_y>=99?1:0;
  wire next_gap=(raw_y>=95&&raw_y<99)||(raw_y>=115&&raw_y<119)||
   (raw_y>=135&&raw_y<139)||(raw_y>=155&&raw_y<159)||
   (raw_y>=175&&raw_y<179)||(raw_y>=195&&raw_y<199)||
   (raw_y>=215&&raw_y<219)||(raw_y>=235&&raw_y<239);
  reg[6:0] band_q;reg[3:0] menu_q;reg gap_q;
  always @(posedge pixel_clk or negedge pixel_rst_n)begin
   if(!pixel_rst_n)begin band_q<=0;menu_q<=0;gap_q<=0;end
   else if(row_end)begin
    band_q<={raw_y>=HEIGHT-25&&raw_y<HEIGHT-9,
     raw_y>=HEIGHT-41&&raw_y<HEIGHT-25,raw_y>=HEIGHT-65&&raw_y<HEIGHT-49,
     raw_y>=79&&raw_y<255,raw_y>=39&&raw_y<55,raw_y>=23&&raw_y<39,raw_y>=7&&raw_y<23};
    menu_q<=next_menu;gap_q<=next_gap;
   end
  end
  assign band=band_q;assign menu_row_pre=menu_q;
  // Only origin[3:0] is used by the compact glyph row. (80+20*r) mod16
  // is exactly {r[1:0],2'b00}; the separately prepared gap keeps full y range.
  assign menu_origin_pre={8'd0,menu_q[1:0],2'b00};assign menu_gap_pre=gap_q;
  // synthesis translate_off
  wire[11:0] next_y=(raw_x==RASTER_HT-1)?(raw_y==RASTER_VT-1?12'd0:raw_y+1'b1):raw_y;
  reg seen=0;reg[11:0] predicted_x,predicted_y;
  always @(posedge pixel_clk or negedge pixel_rst_n)begin
   if(!pixel_rst_n)seen<=0;
   else begin
    if(seen && (raw_x!==predicted_x || raw_y!==predicted_y))$fatal(1,"RASTER_PREDECODE requires exact nominal raster recurrence");
    seen<=1;predicted_x<=raw_x==RASTER_HT-1?12'd0:raw_x+1'b1;predicted_y<=next_y;
   end
  end
  // synthesis translate_on
 end else begin:general_coordinate_bands
  assign band={raw_y>=HEIGHT-24&&raw_y<HEIGHT-8,
   raw_y>=HEIGHT-40&&raw_y<HEIGHT-24,raw_y>=HEIGHT-64&&raw_y<HEIGHT-48,
   raw_y>=80&&raw_y<256,raw_y>=40&&raw_y<56,raw_y>=24&&raw_y<40,raw_y>=8&&raw_y<24};
  assign menu_row_pre=raw_y>=240?8:raw_y>=220?7:raw_y>=200?6:raw_y>=180?5:raw_y>=160?4:raw_y>=140?3:raw_y>=120?2:raw_y>=100?1:0;
  assign menu_origin_pre=80+menu_row_pre*20;
  assign menu_gap_pre=raw_y>=menu_origin_pre+16;
 end endgenerate
 // Formatting bands are independent of whether fault_code is zero.
 // Actual text eligibility below keeps the original zero-fault blank region.
 wire[3:0] format_line=band[0]?0:band[1]?1:band[2]?2:
  (cfg_data[55]&&band[3])?(4'd3+menu_row_pre):band[4]?12:band[5]?13:band[6]?14:0;
 wire hex_cache=band[1]&&index==15;
 wire hex_under=band[2]&&index>=9&&index<=16;
 wire hex_address=band[2]&&index>=27&&index<=34;
 wire hex_fault=(band[2]&&(index==40||index==41))||(band[4]&&(index==13||index==14));
 wire[3:0] fault_payload=(~index[0]^band[4])?cfg_data[43:40]:cfg_data[47:44];
 wire[3:0] hex_payload=({4{hex_cache}}&cache_valid)|
  ({4{hex_under}}&underflows[{underflow_nibble,2'b0}+:4])|
  ({4{hex_address}}&displayed_address[{address_nibble,2'b0}+:4])|
  ({4{hex_fault}}&fault_payload);
 wire fast_hex=hex_cache||hex_under||hex_address||hex_fault;
 reg[11:0] origin_y;reg[5:0] length;reg[1:0] category;reg[3:0] line_id,menu_row;
 reg enabled,override_valid,override_hex;reg[7:0] override_code;
 always @*begin
  origin_y=0;length=0;category=2;line_id=0;menu_row=0;enabled=0;
  if(band[0])begin origin_y=8;length=37;enabled=1;line_id=0;end
  else if(band[1])begin origin_y=24;length=HANDBOOK_PROFILE?47:40;enabled=1;line_id=1;end
  else if(band[2])begin origin_y=40;length=42;enabled=1;line_id=2;end
  else if(cfg_data[55]&&band[3])begin
   category=0;enabled=1;
   menu_row=menu_row_pre;
   origin_y=menu_origin_pre;line_id=3+menu_row;length=35;
   if(menu_gap_pre)enabled=0;
  end else if(band[4]&&cfg_data[47:40]!=0)begin
   category=1;enabled=1;origin_y=HEIGHT-64;length=39;line_id=12;
  end else if(band[5])begin
   category=0;enabled=1;origin_y=HEIGHT-40;length=33;line_id=13;
  end else if(band[6])begin
   category=2;enabled=1;origin_y=HEIGHT-24;length=USER_FEATURES?13:6;line_id=14;
  end
  if(USER_FEATURES&&raw_y>=56&&raw_y<72)begin
   origin_y=56;length=36;enabled=1;line_id=15;category=2;
  end
  override_valid=0;override_code=0;override_hex=0;
  case(format_line)
   0:begin
    if(HD&&index>=11&&index<=14)begin override_valid=1;override_code=index==11?"H":index==12?"D":" ";end
    if(index==21)begin override_valid=1;override_code=49+active_slot;end
    if(index>=27&&index<=29)begin override_valid=1;override_code=decimal_char(decimal_digits[0],29-index);end
    if(index==35||index==36)begin override_valid=1;override_code=decimal_char(decimal_digits[1],36-index);end
   end
   1:begin
    if(cache_valid!=15&&index>=3&&index<=7)begin override_valid=1;
     case(index)3:override_code="L";4:override_code="O";5:override_code="A";6:override_code="D";default:override_code=" ";endcase end
    if(index==15)begin override_valid=1;override_code=0;override_hex=1;end
    if(HANDBOOK_PROFILE)begin
     if(index>=22&&index<=27)begin override_valid=1;
      if(safety_active)case(index)22:override_code="S";23:override_code="A";24:override_code="F";25:override_code="E";default:override_code=" ";endcase
      else if(busy)case(index)22:override_code="W";23:override_code="A";24:override_code="I";25:override_code="T";default:override_code=" ";endcase
      else if(cfg_data[95])case(index)22:override_code="A";23:override_code="U";24:override_code="T";25:override_code="O";default:override_code=" ";endcase
      else case(index)22:override_code="N";23:override_code="O";24:override_code="R";25:override_code="M";26:override_code="A";default:override_code="L";endcase
     end
     if(index>=33&&index<=35)begin override_valid=1;override_code=decimal_char(decimal_digits[6],35-index);end
     if(index==36&&cfg_data[7:0]==255)begin override_valid=1;override_code="+";end
     if(index>=43&&index<=45)begin override_valid=1;override_code=decimal_char(decimal_digits[2],45-index);end
     if(raw_brightness&&index==46)begin override_valid=1;override_code=brightness[8]?"-":"+";end
    end else begin
    if(index>=23&&index<=26&&(safety_active||busy))begin override_valid=1;
     if(safety_active)case(index)23:override_code="S";24:override_code="A";25:override_code="F";default:override_code="E";endcase
     else case(index)23:override_code="W";24:override_code="A";25:override_code="I";default:override_code="T";endcase
    end
    if(index==32||index==33)begin override_valid=1;override_code=index==32?48+(PIPE_LATENCY/10)%10:48+PIPE_LATENCY%10;end
    end
   end
   2:begin
    if(index>=9&&index<=16)begin override_valid=1;override_code=0;override_hex=1;end
    if(index>=27&&index<=34)begin override_valid=1;override_code=0;override_hex=1;end
    if(index==40||index==41)begin override_valid=1;override_code=0;override_hex=1;end
   end
   4:begin
    if(index==12)begin override_valid=1;override_code=raw_brightness?(brightness[8]?"-":"+"):" ";end
    if(HANDBOOK_PROFILE&&raw_brightness&&index<10)begin override_valid=1;
     case(index)0:override_code="O";1:override_code="F";2:override_code="F";3:override_code="S";4:override_code="E";5:override_code="T";default:override_code=" ";endcase
    end
    if(HANDBOOK_PROFILE&&raw_brightness&&index==17)begin override_valid=1;override_code=" ";end
    if(index>=13&&index<=15)begin override_valid=1;override_code=decimal_char(decimal_digits[2],15-index);end
   end
   5:if(index>=12&&index<=14)begin override_valid=1;override_code=decimal_char(decimal_digits[3],14-index);end
   6:if(cfg_data[70]&&index>=12&&index<=19)begin override_valid=1;
    case(index)12:override_code="B";13:override_code="I";14:override_code="L";15:override_code="I";16:override_code="N";17:override_code="E";18:override_code="A";default:override_code="R";endcase end
   7:if(index>=12&&index<=14)begin
    if(HANDBOOK_PROFILE)begin override_valid=1;
     case(scale_select)
      0:override_code=index==13?":":"1";
      1:override_code=index==12?"F":index==13?"I":"T";
      2:override_code=index==12?"1":index==13?"/":"2";
      default:override_code=index==12?"1":index==13?"/":"4";
     endcase
    end else if(!cfg_data[69])begin override_valid=1;override_code=index==13?":":"1";end
   end
   8:if(!cfg_data[68]&&index>=12&&index<=14)begin override_valid=1;override_code=index==12?"O":"F";end
   9:if(index>=12&&index<=14)begin override_valid=1;override_code=decimal_char(decimal_digits[4],14-index);end
   10:if(index==12||index==13)begin override_valid=1;
    case(cfg_data[60:59])0:override_code=index==12?"0":"2";1:override_code=index==12?"0":"5";
     2:override_code=index==12?"1":"0";default:override_code=index==12?"3":"0";endcase end
   11:if(index>=12&&index<=14)begin override_valid=1;override_code=decimal_char(decimal_digits[5],14-index);end
   12:if(index==13||index==14)begin override_valid=1;override_code=0;override_hex=1;end
  endcase
  if(USER_FEATURES&&line_id==14)begin
   override_valid=1;override_hex=0;override_code=" ";
   case(index)0:override_code="U";1:override_code="P";12:override_code="s";default:begin
    if(index>=3&&index<=10)override_code=8'd48+uptime_bcd[(10-index)*4+:4];
   end endcase
  end
  if(USER_FEATURES&&line_id==15)begin
   override_valid=1;override_hex=0;override_code=" ";
   case(index)
    0:override_code="B";1:override_code="R";2:override_code="I";3:override_code="=";
    7:override_code=raw_brightness?(brightness[8]?"-":"+"):"%";
    9:override_code="C";10:override_code="O";11:override_code="N";12:override_code="=";
    17:override_code="S";18:override_code="C";19:override_code="L";20:override_code="=";
    21:override_code=scale_select==0?"1":scale_select==1?"F":"1";
    22:override_code=scale_select==0?":":scale_select==1?"I":"/";
    23:override_code=scale_select==0?"1":scale_select==1?"T":scale_select==2?"2":"4";
    25:override_code="V";26:override_code="O";27:override_code="L";28:override_code="=";
    default:begin
     if(index>=4&&index<=6)override_code=decimal_char(decimal_digits[2],6-index);
     if(index>=13&&index<=15)override_code=decimal_char(decimal_digits[3],15-index);
     if(index>=29&&index<=31)override_code=decimal_char(decimal_digits[4],31-index);
    end
   endcase
  end
 end
 wire[3:0] normal_glyph_row=raw_y[3:0]-origin_y[3:0];
 wire normal_region=enabled&&raw_de&&raw_x>=8&&index<{2'b0,length};
 // SAFE text shares the same ROM storage, with separate read addresses/tags.
 wire[11:0] scaled_x=raw_x>>1,scaled_y=raw_y>>1;
 reg[11:0] safe_ox,safe_oy;reg[5:0] safe_length;reg[5:0] safe_text_offset;
 reg safe_enable;
 (* keep="true" *) wire safe_row_a=scaled_y>=HEIGHT/8&&scaled_y<HEIGHT/8+16;
 (* keep="true" *) wire safe_row_b=scaled_y>=HEIGHT/8+20&&scaled_y<HEIGHT/8+36;
 (* keep="true" *) wire safe_row_c=scaled_y>=HEIGHT*3/8&&scaled_y<HEIGHT*3/8+16;
 localparam[5:0] SAFE_CA=0-(WIDTH/4-36)/8,SAFE_CB=16-(WIDTH/4-16)/8,SAFE_CC=24-(WIDTH/4-108)/8;
 (* keep="true" *) wire[5:0] safe_column_a=scaled_x[8:3]+(raw_x[3]?SAFE_CA:SAFE_CA-6'd1);
 (* keep="true" *) wire[5:0] safe_column_b=scaled_x[8:3]+SAFE_CB;
 (* keep="true" *) wire[5:0] safe_column_c=scaled_x[8:3]+(raw_x[3]?SAFE_CC:SAFE_CC-6'd1);
 wire safe_none=!(safe_row_a||safe_row_b||safe_row_c);

 always @*begin
  safe_length=0;safe_ox=0;safe_oy=0;safe_enable=0;safe_text_offset=0;
  if(safe_row_a)begin
   safe_length=9;safe_ox=WIDTH/4-36;safe_oy=HEIGHT/8;safe_enable=1;safe_text_offset=0;
  end else if(safe_row_b)begin
   safe_length=4;safe_ox=WIDTH/4-16;safe_oy=HEIGHT/8+20;safe_enable=1;safe_text_offset=16;
  end else if(safe_row_c)begin
   safe_length=27;safe_ox=WIDTH/4-108;safe_oy=HEIGHT*3/8;safe_enable=1;safe_text_offset=24;
  end
 end
 wire[12:0] safe_dx={1'b0,scaled_x}-{1'b0,safe_ox},safe_dy={1'b0,scaled_y}-{1'b0,safe_oy};
 wire[5:0] safe_index=safe_dx[8:3];
 wire safe_region=raw_de&&((safe_row_a&&scaled_x>=WIDTH/4-36&&scaled_x<WIDTH/4+36)||
  (safe_row_b&&scaled_x>=WIDTH/4-16&&scaled_x<WIDTH/4+16)||
  (safe_row_c&&scaled_x>=WIDTH/4-108&&scaled_x<WIDTH/4+108));
 wire[2:0] safe_glyph_col=scaled_x[2:0]^((safe_row_a||safe_row_c)?3'd4:3'd0);
 localparam[3:0] SAFE_YA=HEIGHT/8,SAFE_YB=HEIGHT/8+20,SAFE_YC=HEIGHT*3/8;
 wire[3:0] safe_glyph_row=({4{safe_row_a}}&(scaled_y[3:0]-SAFE_YA))|
  ({4{safe_row_b}}&(scaled_y[3:0]-SAFE_YB))|({4{safe_row_c}}&(scaled_y[3:0]-SAFE_YC))|
  ({4{safe_none}}&scaled_y[3:0]);
 (* ram_style="block" *) reg[8:0] text_rom[0:1023];
 (* ram_style="block" *) reg[7:0] glyph_rom[0:1023];
 initial begin if(DESCRIPTOR_TEXT)$readmemh(USER_TEXT_FILE,text_rom);else $readmemh(TEXT_FILE,text_rom);$readmemh(COMPACT_FONT_FILE,glyph_rom);end
 reg[8:0] normal_code1;reg[7:0] safe_code1;reg[7:0] override1;reg override_v1,override_hex1;
 reg[3:0] normal_row1,safe_row1;reg[2:0] normal_col1,normal_col2,normal_col3,safe_col1,safe_col2,safe_col3;
 reg normal_v1,normal_v2,normal_v3,safe_v1,safe_v2,safe_v3;
 reg[9:0] normal_addr2,safe_addr2;reg[7:0] normal_bits3,safe_bits3;
 reg font_dot,safe_dot;
 // The ninth ROM bit selects a compact dynamic descriptor. Decode
 // after the existing character-ROM edge. Capture every live input on that
 // same edge, preserving the original four-clock public pixel contract.
 // Select the small numeric payload BEFORE the character-ROM edge.
 // Only the character descriptor and the relevant digit cross together;
 // there is no need to copy whole32-bit counters or all seven decimal words.
 // Selection uses this SAME raw character address, so even arbitrarily
 // changing live inputs retain the original public four-clock output.
 reg[2:0] decimal_source;
 always @*begin
  case(line_id)
   0:decimal_source=index<32?0:1;
   1:decimal_source=index<40?6:2;
   4:decimal_source=2;5:decimal_source=3;9:decimal_source=4;11:decimal_source=5;
   15:decimal_source=index<8?2:index<16?3:4;
   default:decimal_source=0;
  endcase
 end
 wire[2:0] payload_uf_index=3'd0-index[2:0],payload_address_index=3'd2-index[2:0];
 wire[3:0] payload_uf=underflows[{payload_uf_index,2'b0}+:4];
 wire[3:0] payload_address=cfg_data[8+{payload_address_index,2'b0}+:4];
 wire payload_error_high=line_id==12?index[0]:!index[0];
 wire[3:0] payload_error=payload_error_high?cfg_data[47:44]:cfg_data[43:40];
 wire[3:0] payload_hex=line_id==1?cache_valid:
  line_id==2&&index<35?(index<20?payload_uf:payload_address):payload_error;
 wire[2:0] payload_uptime_index=3'd2-index[2:0];
 reg[5:0] flags_q;reg cache_complete_q;reg[3:0] hex_q,uptime_digit_q;
 reg[1:0] slot_q,scale_q;reg busy_q,safe_q,raw_q,brightness_sign_q;
 reg[9:0] decimal_word_q;
 always @(posedge pixel_clk)begin
  flags_q<={cfg_data[95],cfg_data[70],cfg_data[68],cfg_data[60:59],cfg_data[7:0]==255};
  cache_complete_q<=cache_valid==15;hex_q<=payload_hex;
  uptime_digit_q<=uptime_bcd[{payload_uptime_index,2'b0}+:4];
  slot_q<=active_slot;scale_q<=scale_select;busy_q<=busy;safe_q<=safety_active;
  raw_q<=raw_brightness;brightness_sign_q<=brightness[8];
  decimal_word_q<=decimal_digits[decimal_source];
 end
 function[7:0] render_descriptor;
 input[7:0] op;input[5:0] flags_q;input cache_complete_q;
 input[3:0] hex_q,uptime_digit_q;input[1:0] slot_q,scale_q;
 input busy_q,safe_q,raw_q,brightness_sign_q;input[9:0] decimal_word;
 begin
  case(op)
   8'd0:render_descriptor=HD?8'h48:8'h42;
   8'd1:render_descriptor=HD?8'h44:8'h41;
   8'd2:render_descriptor=HD?8'h20:8'h53;
   8'd3:render_descriptor=HD?8'h20:8'h45;
   8'd4:render_descriptor=8'd49+slot_q;
   8'd5:render_descriptor=decimal_char(decimal_word,2'd2);
   8'd6:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd7:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd8:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd9:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd10:render_descriptor=!cache_complete_q?8'h4c : 8'h52;
   8'd11:render_descriptor=!cache_complete_q?8'h4f : 8'h45;
   8'd12:render_descriptor=!cache_complete_q?8'h41 : 8'h41;
   8'd13:render_descriptor=!cache_complete_q?8'h44 : 8'h44;
   8'd14:render_descriptor=!cache_complete_q?8'h20 : 8'h59;
   8'd15:render_descriptor=hexchar(hex_q);
   8'd16:render_descriptor=safe_q?8'h53:busy_q?8'h57:flags_q[5]?8'h41:8'h4e;
   8'd17:render_descriptor=safe_q?8'h41:busy_q?8'h41:flags_q[5]?8'h55:8'h4f;
   8'd18:render_descriptor=safe_q?8'h46:busy_q?8'h49:flags_q[5]?8'h54:8'h52;
   8'd19:render_descriptor=safe_q?8'h45:busy_q?8'h54:flags_q[5]?8'h4f:8'h4d;
   8'd20:render_descriptor=safe_q?8'h20:busy_q?8'h20:flags_q[5]?8'h20:8'h41;
   8'd21:render_descriptor=safe_q?8'h20:busy_q?8'h20:flags_q[5]?8'h20:8'h4c;
   8'd22:render_descriptor=decimal_char(decimal_word,2'd2);
   8'd23:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd24:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd25:render_descriptor=flags_q[0]?8'h2b : 8'h20;
   8'd26:render_descriptor=decimal_char(decimal_word,2'd2);
   8'd27:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd28:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd29:render_descriptor=raw_q?(brightness_sign_q?8'h2d:8'h2b) : 8'h25;
   8'd30:render_descriptor=hexchar(hex_q);
   8'd31:render_descriptor=hexchar(hex_q);
   8'd32:render_descriptor=hexchar(hex_q);
   8'd33:render_descriptor=hexchar(hex_q);
   8'd34:render_descriptor=hexchar(hex_q);
   8'd35:render_descriptor=hexchar(hex_q);
   8'd36:render_descriptor=hexchar(hex_q);
   8'd37:render_descriptor=hexchar(hex_q);
   8'd38:render_descriptor=hexchar(hex_q);
   8'd39:render_descriptor=hexchar(hex_q);
   8'd40:render_descriptor=hexchar(hex_q);
   8'd41:render_descriptor=hexchar(hex_q);
   8'd42:render_descriptor=hexchar(hex_q);
   8'd43:render_descriptor=hexchar(hex_q);
   8'd44:render_descriptor=hexchar(hex_q);
   8'd45:render_descriptor=hexchar(hex_q);
   8'd46:render_descriptor=hexchar(hex_q);
   8'd47:render_descriptor=hexchar(hex_q);
   8'd48:render_descriptor=raw_q?8'h4f : 8'h42;
   8'd49:render_descriptor=raw_q?8'h46 : 8'h52;
   8'd50:render_descriptor=raw_q?8'h46 : 8'h49;
   8'd51:render_descriptor=raw_q?8'h53 : 8'h47;
   8'd52:render_descriptor=raw_q?8'h45 : 8'h48;
   8'd53:render_descriptor=raw_q?8'h54 : 8'h54;
   8'd54:render_descriptor=raw_q?8'h20 : 8'h4e;
   8'd55:render_descriptor=raw_q?8'h20 : 8'h45;
   8'd56:render_descriptor=raw_q?8'h20 : 8'h53;
   8'd57:render_descriptor=raw_q?(brightness_sign_q?8'h2d:8'h2b):8'h20;
   8'd58:render_descriptor=raw_q?8'h20 : 8'h25;
   8'd59:render_descriptor=decimal_char(decimal_word,2'd2);
   8'd60:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd61:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd62:render_descriptor=flags_q[4]?8'h42 : 8'h4e;
   8'd63:render_descriptor=flags_q[4]?8'h49 : 8'h45;
   8'd64:render_descriptor=flags_q[4]?8'h4c : 8'h41;
   8'd65:render_descriptor=flags_q[4]?8'h49 : 8'h52;
   8'd66:render_descriptor=flags_q[4]?8'h4e : 8'h45;
   8'd67:render_descriptor=flags_q[4]?8'h45 : 8'h53;
   8'd68:render_descriptor=flags_q[4]?8'h41 : 8'h54;
   8'd69:render_descriptor=flags_q[4]?8'h52 : 8'h20;
   8'd70:render_descriptor=scale_q==0?8'h31:scale_q==1?8'h46:scale_q==2?8'h31:8'h31;
   8'd71:render_descriptor=scale_q==0?8'h3a:scale_q==1?8'h49:scale_q==2?8'h2f:8'h2f;
   8'd72:render_descriptor=scale_q==0?8'h31:scale_q==1?8'h54:scale_q==2?8'h32:8'h34;
   8'd73:render_descriptor=!flags_q[3]?8'h4f : 8'h4f;
   8'd74:render_descriptor=!flags_q[3]?8'h46 : 8'h4e;
   8'd75:render_descriptor=!flags_q[3]?8'h46 : 8'h20;
   8'd76:render_descriptor=decimal_char(decimal_word,2'd2);
   8'd77:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd78:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd79:render_descriptor=flags_q[2:1]==0?8'h30:flags_q[2:1]==1?8'h30:flags_q[2:1]==2?8'h31:8'h33;
   8'd80:render_descriptor=flags_q[2:1]==0?8'h32:flags_q[2:1]==1?8'h35:flags_q[2:1]==2?8'h30:8'h30;
   8'd81:render_descriptor=decimal_char(decimal_word,2'd2);
   8'd82:render_descriptor=decimal_char(decimal_word,2'd1);
   8'd83:render_descriptor=decimal_char(decimal_word,2'd0);
   8'd84:render_descriptor=8'd48+uptime_digit_q;
   8'd85:render_descriptor=8'd48+uptime_digit_q;
   8'd86:render_descriptor=8'd48+uptime_digit_q;
   8'd87:render_descriptor=8'd48+uptime_digit_q;
   8'd88:render_descriptor=8'd48+uptime_digit_q;
   8'd89:render_descriptor=8'd48+uptime_digit_q;
   8'd90:render_descriptor=8'd48+uptime_digit_q;
   8'd91:render_descriptor=8'd48+uptime_digit_q;
   8'd92:render_descriptor=raw_q?(brightness_sign_q?8'h2d:8'h2b):8'h25;
   default:render_descriptor=8'h20;
  endcase
 end endfunction
 wire[7:0] normal_effective=DESCRIPTOR_TEXT?
  (normal_code1[8]?render_descriptor(normal_code1[7:0],flags_q,cache_complete_q,hex_q,uptime_digit_q,slot_q,scale_q,busy_q,safe_q,raw_q,brightness_sign_q,decimal_word_q):normal_code1[7:0]):
  (override_v1?(override_hex1?hexchar(override1[3:0]):override1):normal_code1[7:0]);
 wire[9:0] normal_text_address=DESCRIPTOR_TEXT&&line_id==15?
  (index<29?10'd227+index:10'd291+index-10'd29):{line_id,index[5:0]};


 wire[3:0] nr=normal_row1-1'b1,sr=safe_row1-1'b1;
 // Parallel constant columns avoid a raw_y -> selected origin -> 13-bit
 // subtract -> offset-add chain on the shared synchronous text ROM port.
 wire[5:0] safe_text_column=({6{safe_row_a}}&safe_column_a)|({6{safe_row_b}}&safe_column_b)|
  ({6{safe_row_c}}&safe_column_c)|({6{safe_none}}&scaled_x[8:3]);
 // Synchronous, two-read-port ROMs. No reset on ROM outputs for RAM inference.
 always @(posedge pixel_clk)begin
  normal_code1<=text_rom[normal_text_address];safe_code1<=text_rom[{4'hf,safe_text_column}];
  normal_bits3<=glyph_rom[normal_addr2];safe_bits3<=glyph_rom[safe_addr2];
 end
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin override1<=0;override_v1<=0;override_hex1<=0;normal_row1<=0;safe_row1<=0;
   normal_col1<=0;normal_col2<=0;normal_col3<=0;safe_col1<=0;safe_col2<=0;safe_col3<=0;
   normal_v1<=0;normal_v2<=0;normal_v3<=0;safe_v1<=0;safe_v2<=0;safe_v3<=0;
   normal_addr2<=0;safe_addr2<=0;font_dot<=0;safe_dot<=0;
  end else begin
   override1<=DESCRIPTOR_TEXT?0:fast_hex?{4'd0,hex_payload}:override_code;override_v1<=!DESCRIPTOR_TEXT&&override_valid;override_hex1<=!DESCRIPTOR_TEXT&&override_hex;
   normal_row1<=normal_glyph_row;safe_row1<=safe_glyph_row;normal_col1<=raw_x[2:0];safe_col1<=safe_glyph_col;
   normal_v1<=normal_region;safe_v1<=safe_region;
   normal_addr2<={normal_effective[6:0],nr[3:1]};safe_addr2<={safe_code1[6:0],sr[3:1]};
   normal_v2<=normal_v1&&!normal_effective[7]&&normal_row1!=0&&normal_row1!=15;
   safe_v2<=safe_v1&&!safe_code1[7]&&safe_row1!=0&&safe_row1!=15;
   normal_col2<=normal_col1;safe_col2<=safe_col1;
   normal_v3<=normal_v2;safe_v3<=safe_v2;normal_col3<=normal_col2;safe_col3<=safe_col2;
   font_dot<=normal_v3&&normal_bits3[7-normal_col3];safe_dot<=safe_v3&&safe_bits3[7-safe_col3];
  end
 end
 wire menu_panel=cfg_data[55]&&raw_x>=4&&raw_x<300&&raw_y>=76&&raw_y<260;
 wire[8:0] field_offset={2'b0,cfg_data[58:56],4'b0}+{4'b0,cfg_data[58:56],2'b0};
 wire[8:0] selected_begin=9'd100+field_offset,selected_end=9'd116+field_offset;
 wire selected=menu_panel&&raw_y>=selected_begin&&raw_y<selected_end;
 wire warning_border=cfg_data[47:40]!=0&&(raw_x<4||raw_x>=WIDTH-4||raw_y<4||raw_y>=HEIGHT-4);
 wire column_edge,column_fill;wire[1:0] column_colour;
 generate if(VOLUME_COLUMNS)begin:volume_columns
  v3_volume_column #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) column(
   .clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(frame_start),.energy(energy),.volume(cfg_data[67:61]),
   .x(raw_x),.y(raw_y),.de(raw_de),.edge_pixel(column_edge),.fill_pixel(column_fill),.colour(column_colour));
 end else begin:no_volume_columns
  assign column_edge=0;assign column_fill=0;assign column_colour=0;
 end endgenerate
 wire setting_edge,setting_fill,setting_caption;wire[6:0] setting_level;
 generate if(VOLUME_SETTING)begin:volume_setting
  v3_volume_setting_column #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) column(
   .clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(frame_start),.volume(cfg_data[67:61]),
   .x(raw_x),.y(raw_y),.de(raw_de),.edge_pixel(setting_edge),.fill_pixel(setting_fill),.caption_pixel(setting_caption),.level(setting_level));
 end else begin:no_volume_setting
  assign setting_edge=0;assign setting_fill=0;assign setting_caption=0;assign setting_level=0;
 end endgenerate
 reg[3:0] setting_fill_pipe,setting_caption_pipe;
 always @(posedge pixel_clk or negedge pixel_rst_n)
  if(!pixel_rst_n)begin setting_fill_pipe<=0;setting_caption_pipe<=0;end
  else begin setting_fill_pipe<={setting_fill_pipe[2:0],setting_fill};setting_caption_pipe<={setting_caption_pipe[2:0],setting_caption};end
 reg[3:0] column_fill_pipe;reg[1:0] column_colour_pipe[0:3];integer ci;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin column_fill_pipe<=0;for(ci=0;ci<4;ci=ci+1)column_colour_pipe[ci]<=0;end
  else begin column_fill_pipe<={column_fill_pipe[2:0],column_fill};column_colour_pipe[0]<=column_colour;
   for(ci=1;ci<4;ci=ci+1)column_colour_pipe[ci]<=column_colour_pipe[ci-1];end
 end
 wire[15:0] column_rgb=column_colour_pipe[3]==2?16'hf800:column_colour_pipe[3]==1?16'hffe0:16'h07e0;
 wire bar_box=!USER_FEATURES&&raw_x>=80&&raw_x<282&&raw_y>=HEIGHT-22&&raw_y<HEIGHT-10;
 // Constant dark backing keeps text/scope visible even on a white BMP.
 // Reuse the retired bar's existing four-clock eligibility pipeline.
 wire user_panel=USER_FEATURES&&raw_de&&(
  (raw_x>=8&&raw_x<296&&raw_y>=56&&raw_y<72)||
  (raw_x>=8&&raw_x<112&&raw_y>=HEIGHT-24&&raw_y<HEIGHT-8)||
  (raw_x>=(FLEX_SPECTRUM?WIDTH-304:WIDTH-272)&&raw_x<WIDTH-16&&raw_y>=(FLEX_SPECTRUM?HEIGHT-160:HEIGHT-130)&&raw_y<(FLEX_SPECTRUM?HEIGHT-36:HEIGHT-62)));
 wire bar_edge=user_panel||setting_edge||column_edge||bar_box&&(raw_x==80||raw_x==281||raw_y==HEIGHT-22||raw_y==HEIGHT-11);
 wire bar_fill=column_fill||bar_box&&raw_x>80&&raw_x<81+energy*2&&raw_y>HEIGHT-22&&raw_y<HEIGHT-11;
 wire wave_trace,wave_grid;wire[15:0] wave_colour;
 wire spectrum_ready;wire[15:0] spectrum_sequence;
 generate if(USER_FEATURES&&FLEX_SPECTRUM)begin:spectrum
  v3_audio_spectrum #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) analyzer(
   .clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(frame_start),.pcm_valid(wave_pcm_valid),.pcm_left(wave_pcm_left),
   .x(raw_x),.y(raw_y),.de(raw_de),.trace_pixel(wave_trace),.grid_pixel(wave_grid),.colour(wave_colour),.ready(spectrum_ready),.spectrum_sequence(spectrum_sequence),.dominant_bin(),.peak_height());
 end else if(USER_FEATURES)begin:waveform
  assign spectrum_ready=0;assign spectrum_sequence=0;
  assign wave_colour=16'h05bf;
  v3_pcm_waveform #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) scope(
   .clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(frame_start),.pcm_valid(wave_pcm_valid),.pcm_left(wave_pcm_left),
   .x(raw_x),.y(raw_y),.de(raw_de),.trace_pixel(wave_trace),.grid_pixel(wave_grid),.ready());
 end else begin:no_waveform assign spectrum_ready=0;assign spectrum_sequence=0;assign wave_trace=0;assign wave_grid=0;assign wave_colour=0;end endgenerate
 reg[2:0] wave_trace_pipe,wave_grid_pipe;reg[15:0] wave_colour_pipe[0:2];integer spectrum_ci;
 always @(posedge pixel_clk or negedge pixel_rst_n)
  if(!pixel_rst_n)for(spectrum_ci=0;spectrum_ci<3;spectrum_ci=spectrum_ci+1)wave_colour_pipe[spectrum_ci]<=0;
  else begin wave_colour_pipe[0]<=wave_colour;for(spectrum_ci=1;spectrum_ci<3;spectrum_ci=spectrum_ci+1)wave_colour_pipe[spectrum_ci]<=wave_colour_pipe[spectrum_ci-1];end
 reg[3:0] uptime_pipe;
 always @(posedge pixel_clk or negedge pixel_rst_n)
  if(!pixel_rst_n)begin wave_trace_pipe<=0;wave_grid_pipe<=0;uptime_pipe<=0;end
  else begin wave_trace_pipe<={wave_trace_pipe[1:0],wave_trace};wave_grid_pipe<={wave_grid_pipe[1:0],wave_grid};
   uptime_pipe<={uptime_pipe[2:0],USER_FEATURES&&line_id==14&&raw_x>=8&&index<13};end
 reg[1:0] cat[0:3];reg[7:0] oa[0:3];
 reg[3:0] panel_pipe,select_pipe,border_pipe,bar_edge_pipe,bar_fill_pipe,de_pipe;
 integer i,j;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin panel_pipe<=0;select_pipe<=0;border_pipe<=0;bar_edge_pipe<=0;bar_fill_pipe<=0;de_pipe<=0;
   for(i=0;i<4;i=i+1)begin cat[i]<=0;oa[i]<=0;end
  end else begin cat[0]<=category;oa[0]<=cfg_data[78:71];
   for(i=1;i<4;i=i+1)begin cat[i]<=cat[i-1];oa[i]<=oa[i-1];end
   panel_pipe<={panel_pipe[2:0],menu_panel};select_pipe<={select_pipe[2:0],selected};border_pipe<={border_pipe[2:0],warning_border};
   de_pipe<={de_pipe[2:0],raw_de};bar_edge_pipe<={bar_edge_pipe[2:0],bar_edge};bar_fill_pipe<={bar_fill_pipe[2:0],bar_fill};end
 end
 assign osd_rgb565=font_dot&&cat[3]==0?16'hffff:select_pipe[3]?16'h05bf:16'h1086;
 assign osd_alpha=de_pipe[3]&&((font_dot&&cat[3]==0)||panel_pipe[3])?oa[3]:0;
 assign emergency_rgb565=16'hf800;
 assign emergency_alpha=de_pipe[3]&&(border_pipe[3]||(font_dot&&cat[3]==1))?8'd224:0;
 assign hud_rgb565=wave_trace_pipe[2]?wave_colour_pipe[2]:setting_caption_pipe[3]||(font_dot&&cat[3]==2)?16'hffff:setting_fill_pipe[3]?16'h05bf:bar_fill_pipe[3]?(column_fill_pipe[3]?column_rgb:16'h07e0):wave_grid_pipe[2]?16'h7bef:USER_FEATURES?16'd0:16'h7bef;
 assign hud_alpha=de_pipe[3]&&(wave_trace_pipe[2]||wave_grid_pipe[2]||(font_dot&&cat[3]==2)||bar_fill_pipe[3]||bar_edge_pipe[3]||setting_fill_pipe[3]||setting_caption_pipe[3])?8'd224:0;
 wire[12:0] dy=raw_y>=HEIGHT/2?raw_y-HEIGHT/2:HEIGHT/2-raw_y;
 wire arrow=(raw_x>=WIDTH/2-96&&raw_x<WIDTH/2-32&&dy<=(raw_x-(WIDTH/2-96))/2)||
  (raw_x>=WIDTH/2-32&&raw_x<WIDTH/2+96&&dy<=12);
 wire safe_border=raw_x<4||raw_x>=WIDTH-4||raw_y<4||raw_y>=HEIGHT-4;
 reg[15:0] safe_geometry[0:3];
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)for(j=0;j<4;j=j+1)safe_geometry[j]<=0;
  else begin safe_geometry[0]<=safe_border?(blink?16'hf800:16'h7800):arrow&&blink?16'h07e0:16'h1800;
   for(j=1;j<4;j=j+1)safe_geometry[j]<=safe_geometry[j-1];end
 end
 assign safe_rgb565=de_pipe[3]?(uptime_pipe[3]?(font_dot?16'hffff:16'd0):safe_dot?16'h07e0:safe_geometry[3]):16'd0;
endmodule

// Output-gain VU estimate, separate from the handbook pre-volume energy bar.
// One immutable frame snapshot; exact floor(min(E,100)*min(V,100)/100).
// Seven serial shift/add clocks, at most100 subtract clocks. No DSP/BRAM.
// Publishes during scan line0, long before the column first appears. It is
// an amplitude/gain meter, not frequency analysis or an FFT spectrum.
module v3_volume_column #(parameter integer WIDTH=640,HEIGHT=480)(
 input wire clk,rst_n,frame_start,input wire[6:0] energy,volume,
 input wire[11:0] x,y,input wire de,
 output wire edge_pixel,fill_pixel,output wire[1:0] colour,
 output reg[6:0] level,output wire busy);
 // Two DSP stages replace serial shift/add and the14-bit subtract loop.
 // floor(p/100)=(p*5243)>>19 for all p=0..10000 (error<0.003).
 // Keep the original7-clock calculation interval and quotient-count wait:
 // level,busy and every raster output remain exact on each clock edge.
 reg[1:0] state;reg[3:0] bits_left;reg[6:0] energy_q,volume_q,target,remaining;
 reg[13:0] product_q;
 (* dsp_style="yes" *) wire[13:0] sample_product=energy_q*volume_q;
 (* dsp_style="yes" *) wire[26:0] reciprocal_product=product_q*13'd5243;
 wire[6:0] quotient=reciprocal_product[25:19];
 assign busy=state!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;bits_left<=0;energy_q<=0;volume_q<=0;target<=0;remaining<=0;product_q<=0;level<=0;end
  else if(frame_start)begin
   state<=1;bits_left<=7;energy_q<=energy>100?7'd100:energy;volume_q<=volume>100?7'd100:volume;
   target<=0;remaining<=0;product_q<=0;
  end else case(state)
   1:begin bits_left<=bits_left-1'b1;
    if(bits_left==7)product_q<=sample_product;
    if(bits_left==6)begin target<=quotient;remaining<=quotient;end
    if(bits_left==1)state<=2;
   end
   2:if(remaining!=0)remaining<=remaining-1'b1;
     else begin level<=target;state<=0;end
   default:;
  endcase
 end
 wire box=de&&x>=WIDTH-49&&x<=WIDTH-23&&y>=HEIGHT-171&&y<=HEIGHT-69;
 assign edge_pixel=box&&(x==WIDTH-49||x==WIDTH-23||y==HEIGHT-171||y==HEIGHT-69);
 wire[11:0] rise=HEIGHT-70-y;
 wire gap=rise==10||rise==20||rise==30||rise==40||rise==50||rise==60||rise==70||rise==80||rise==90;
 assign fill_pixel=box&&!edge_pixel&&rise>=1&&rise<=100&&rise<=level&&!gap;
 assign colour=rise>80?2'd2:rise>50?2'd1:2'd0;
endmodule

// Explicit user volume, independent of the pre-volume source energy. The VU
// estimate beside it remains unchanged. Capture only in vertical blank; no
// arithmetic, DSP, RAM or extra pixel latency. Fixed seven-row captions use
// a small local bitmap so the existing two font ROM ports remain intact.
module v3_volume_setting_column #(parameter integer WIDTH=640,HEIGHT=480)(
 input wire clk,rst_n,frame_start,input wire[6:0] volume,
 input wire[11:0] x,y,input wire de,
 output wire edge_pixel,fill_pixel,caption_pixel,output reg[6:0] level);
 always @(posedge clk or negedge rst_n)
  if(!rst_n)level<=0;
  else if(frame_start)level<=volume>100?7'd100:volume;
 wire box=de&&x>=WIDTH-86&&x<=WIDTH-60&&y>=HEIGHT-171&&y<=HEIGHT-69;
 assign edge_pixel=box&&(x==WIDTH-86||x==WIDTH-60||y==HEIGHT-171||y==HEIGHT-69);
 // Inside the101-row box the true positive height fits seven bits; all other
 // coordinates are excluded independently. Modulo128 preserves that height.
 localparam[6:0] BASE_Y=HEIGHT-70;
 wire[6:0] rise=BASE_Y-y[6:0];
 wire gap=rise==10||rise==20||rise==30||rise==40||rise==50||rise==60||rise==70||rise==80||rise==90;
 assign fill_pixel=box&&!edge_pixel&&rise>=1&&rise<=100&&rise<=level&&!gap;
 wire[11:0] lx=x-(WIDTH-81),ux=x-(WIDTH-42),ly=y-(HEIGHT-60);
 reg[4:0] gv,go,gl,gu;
 always @*begin
  gv=0;go=0;gl=0;gu=0;
  case(ly)
   0,1,2,3,4:begin gv=5'b10001;go=ly==0?5'b01110:5'b10001;gl=5'b10000;gu=5'b10001;end
   5:begin gv=5'b01010;go=5'b10001;gl=5'b10000;gu=5'b10001;end
   6:begin gv=5'b00100;go=5'b01110;gl=5'b11111;gu=5'b01110;end
   default:;
  endcase
 end
 wire vol_label=ly<7&&((lx<5&&gv[4-lx])||(lx>=6&&lx<11&&go[10-lx])||(lx>=12&&lx<17&&gl[16-lx]));
 wire vu_label=ly<7&&((ux<5&&gv[4-ux])||(ux>=6&&ux<11&&gu[10-ux]));
 assign caption_pixel=de&&(vol_label||vu_label);
endmodule
