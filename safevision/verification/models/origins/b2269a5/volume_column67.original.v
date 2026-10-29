


module v3_status_layers #(
 parameter integer HD=0,HANDBOOK_PROFILE=0,VOLUME_COLUMNS=0,PIXEL_HZ=HD?74250000:25175000,PIPE_LATENCY=21,
 parameter FONT_FILE="../../../assets/fonts/font8x16.mem",
 parameter COMPACT_FONT_FILE="../../assets/fonts/font8x16_compact.mem",
 parameter TEXT_FILE="../../assets/fonts/v3_status_text.mem"
)(
 input wire pixel_clk,pixel_rst_n,
 input wire[11:0] raw_x,raw_y,input wire raw_de,frame_start,
 input wire[(HANDBOOK_PROFILE?99:96)-1:0] cfg_data,input wire[3:0] cache_valid,
 input wire[31:0] underflows,input wire[1:0] active_slot,
 input wire[7:0] generation,input wire busy,safety_active,
 output wire[15:0] osd_rgb565,emergency_rgb565,hud_rgb565,safe_rgb565,
 output wire[7:0] osd_alpha,emergency_alpha,hud_alpha
);
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

 wire[7:0] index=raw_x[10:3]-8'd1;
 reg[11:0] origin_y;reg[5:0] length;reg[1:0] category;reg[3:0] line_id,menu_row;
 reg enabled,override_valid;reg[7:0] override_code;
 always @*begin
  origin_y=0;length=0;category=2;line_id=0;menu_row=0;enabled=0;
  if(raw_y>=8&&raw_y<24)begin origin_y=8;length=37;enabled=1;line_id=0;end
  else if(raw_y>=24&&raw_y<40)begin origin_y=24;length=HANDBOOK_PROFILE?47:40;enabled=1;line_id=1;end
  else if(raw_y>=40&&raw_y<56)begin origin_y=40;length=42;enabled=1;line_id=2;end
  else if(cfg_data[55]&&raw_y>=80&&raw_y<256)begin
   category=0;enabled=1;
   menu_row=raw_y>=240?8:raw_y>=220?7:raw_y>=200?6:raw_y>=180?5:raw_y>=160?4:raw_y>=140?3:raw_y>=120?2:raw_y>=100?1:0;
   origin_y=80+menu_row*20;line_id=3+menu_row;length=35;
   if(raw_y>=origin_y+16)enabled=0;
  end else if(raw_y>=HEIGHT-64&&raw_y<HEIGHT-48&&cfg_data[47:40]!=0)begin
   category=1;enabled=1;origin_y=HEIGHT-64;length=39;line_id=12;
  end else if(raw_y>=HEIGHT-40&&raw_y<HEIGHT-24)begin
   category=0;enabled=1;origin_y=HEIGHT-40;length=33;line_id=13;
  end else if(raw_y>=HEIGHT-24&&raw_y<HEIGHT-8)begin
   category=2;enabled=1;origin_y=HEIGHT-24;length=6;line_id=14;
  end
  override_valid=0;override_code=0;
  case(line_id)
   0:begin
    if(HD&&index>=11&&index<=14)begin override_valid=1;override_code=index==11?"H":index==12?"D":" ";end
    if(index==21)begin override_valid=1;override_code=49+active_slot;end
    if(index>=27&&index<=29)begin override_valid=1;override_code=decimal_char(decimal_digits[0],29-index);end
    if(index==35||index==36)begin override_valid=1;override_code=decimal_char(decimal_digits[1],36-index);end
   end
   1:begin
    if(cache_valid!=15&&index>=3&&index<=7)begin override_valid=1;
     case(index)3:override_code="L";4:override_code="O";5:override_code="A";6:override_code="D";default:override_code=" ";endcase end
    if(index==15)begin override_valid=1;override_code=hexchar(cache_valid);end
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
    if(index>=9&&index<=16)begin override_valid=1;override_code=hexchar(underflows[(16-index)*4+:4]);end
    if(index>=27&&index<=34)begin override_valid=1;override_code=hexchar(cfg_data[8+(34-index)*4+:4]);end
    if(index==40||index==41)begin override_valid=1;override_code=hexchar(index==40?cfg_data[47:44]:cfg_data[43:40]);end
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
   12:if(index==13||index==14)begin override_valid=1;override_code=hexchar(index==13?cfg_data[47:44]:cfg_data[43:40]);end
  endcase
 end
 wire[3:0] normal_glyph_row=raw_y[3:0]-origin_y[3:0];
 wire normal_region=enabled&&raw_de&&raw_x>=8&&index<{2'b0,length};

 wire[11:0] scaled_x=raw_x>>1,scaled_y=raw_y>>1;
 reg[11:0] safe_ox,safe_oy;reg[5:0] safe_length;reg[5:0] safe_text_offset;
 reg safe_enable;
 always @*begin
  safe_length=0;safe_ox=0;safe_oy=0;safe_enable=0;safe_text_offset=0;
  if(scaled_y>=HEIGHT/8&&scaled_y<HEIGHT/8+16)begin
   safe_length=9;safe_ox=WIDTH/4-36;safe_oy=HEIGHT/8;safe_enable=1;safe_text_offset=0;
  end else if(scaled_y>=HEIGHT/8+20&&scaled_y<HEIGHT/8+36)begin
   safe_length=4;safe_ox=WIDTH/4-16;safe_oy=HEIGHT/8+20;safe_enable=1;safe_text_offset=16;
  end else if(scaled_y>=HEIGHT*3/8&&scaled_y<HEIGHT*3/8+16)begin
   safe_length=27;safe_ox=WIDTH/4-108;safe_oy=HEIGHT*3/8;safe_enable=1;safe_text_offset=24;
  end
 end
 wire[12:0] safe_dx={1'b0,scaled_x}-{1'b0,safe_ox},safe_dy={1'b0,scaled_y}-{1'b0,safe_oy};
 wire[5:0] safe_index=safe_dx[8:3];
 wire safe_region=safe_enable&&raw_de&&scaled_x>=safe_ox&&scaled_y>=safe_oy&&safe_dx<{4'b0,safe_length,3'b0}&&safe_dy<16;
 (* ram_style="block" *) reg[7:0] text_rom[0:1023];
 (* ram_style="block" *) reg[7:0] glyph_rom[0:1023];
 initial begin $readmemh(TEXT_FILE,text_rom);$readmemh(COMPACT_FONT_FILE,glyph_rom);end
 reg[7:0] normal_code1,safe_code1;reg[7:0] override1;reg override_v1;
 reg[3:0] normal_row1,safe_row1;reg[2:0] normal_col1,normal_col2,normal_col3,safe_col1,safe_col2,safe_col3;
 reg normal_v1,normal_v2,normal_v3,safe_v1,safe_v2,safe_v3;
 reg[9:0] normal_addr2,safe_addr2;reg[7:0] normal_bits3,safe_bits3;
 reg font_dot,safe_dot;
 wire[7:0] normal_effective=override_v1?override1:normal_code1;
 wire[3:0] nr=normal_row1-1'b1,sr=safe_row1-1'b1;
 wire[5:0] safe_text_column=safe_text_offset+safe_index;

 always @(posedge pixel_clk)begin
  normal_code1<=text_rom[{line_id,index[5:0]}];safe_code1<=text_rom[{4'hf,safe_text_column}];
  normal_bits3<=glyph_rom[normal_addr2];safe_bits3<=glyph_rom[safe_addr2];
 end
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin override1<=0;override_v1<=0;normal_row1<=0;safe_row1<=0;
   normal_col1<=0;normal_col2<=0;normal_col3<=0;safe_col1<=0;safe_col2<=0;safe_col3<=0;
   normal_v1<=0;normal_v2<=0;normal_v3<=0;safe_v1<=0;safe_v2<=0;safe_v3<=0;
   normal_addr2<=0;safe_addr2<=0;font_dot<=0;safe_dot<=0;
  end else begin
   override1<=override_code;override_v1<=override_valid;
   normal_row1<=normal_glyph_row;safe_row1<=safe_dy[3:0];normal_col1<=raw_x[2:0];safe_col1<=safe_dx[2:0];
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
 reg[3:0] column_fill_pipe;reg[1:0] column_colour_pipe[0:3];integer ci;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin column_fill_pipe<=0;for(ci=0;ci<4;ci=ci+1)column_colour_pipe[ci]<=0;end
  else begin column_fill_pipe<={column_fill_pipe[2:0],column_fill};column_colour_pipe[0]<=column_colour;
   for(ci=1;ci<4;ci=ci+1)column_colour_pipe[ci]<=column_colour_pipe[ci-1];end
 end
 wire[15:0] column_rgb=column_colour_pipe[3]==2?16'hf800:column_colour_pipe[3]==1?16'hffe0:16'h07e0;
 wire bar_box=raw_x>=80&&raw_x<282&&raw_y>=HEIGHT-22&&raw_y<HEIGHT-10;
 wire bar_edge=column_edge||bar_box&&(raw_x==80||raw_x==281||raw_y==HEIGHT-22||raw_y==HEIGHT-11);
 wire bar_fill=column_fill||bar_box&&raw_x>80&&raw_x<81+energy*2&&raw_y>HEIGHT-22&&raw_y<HEIGHT-11;
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
 assign hud_rgb565=font_dot&&cat[3]==2?16'hffff:bar_fill_pipe[3]?(column_fill_pipe[3]?column_rgb:16'h07e0):16'h7bef;
 assign hud_alpha=de_pipe[3]&&((font_dot&&cat[3]==2)||bar_fill_pipe[3]||bar_edge_pipe[3])?8'd224:0;
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
 assign safe_rgb565=de_pipe[3]?(safe_dot?16'h07e0:safe_geometry[3]):16'd0;
endmodule


module v3_volume_column #(parameter integer WIDTH=640,HEIGHT=480)(
 input wire clk,rst_n,frame_start,input wire[6:0] energy,volume,
 input wire[11:0] x,y,input wire de,
 output wire edge_pixel,fill_pixel,output wire[1:0] colour,
 output reg[6:0] level,output wire busy);
 reg[1:0] state;reg[3:0] bits_left;reg[6:0] multiplier,quotient;
 reg[13:0] term,acc;
 wire[13:0] added=acc+(multiplier[0]?term:14'd0);
 assign busy=state!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;bits_left<=0;multiplier<=0;quotient<=0;term<=0;acc<=0;level<=0;end
  else if(frame_start)begin
   state<=1;bits_left<=7;multiplier<=volume>100?7'd100:volume;
   term<={7'd0,energy>100?7'd100:energy};acc<=0;quotient<=0;
  end else case(state)
   1:begin acc<=added;term<=term<<1;multiplier<=multiplier>>1;bits_left<=bits_left-1'b1;
    if(bits_left==1)state<=2;end
   2:if(acc>=100)begin acc<=acc-14'd100;quotient<=quotient+1'b1;end
     else begin level<=quotient;state<=0;end
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
