// Real PCM spectrum, pixel clock only,512-point radix2 DIT FFT with periodic
// Hann window. One scaled butterfly/DSP datapath; one read and one write port.
// Capture pauses only this observer while FFT runs; HDMI audio is never stalled.
// Completed32-band spectra are committed at a video frame boundary.
module v3_audio_spectrum #(parameter WIDTH=640,HEIGHT=480,
 parameter TWIDDLE_FILE="v3_spectrum_twiddle.mem")(
 input wire clk,rst_n,frame_start,pcm_valid,input wire[23:0] pcm_left,
 input wire[11:0] x,y,input wire de,
 output reg trace_pixel,grid_pixel,output reg[15:0] colour,
 output reg ready,output reg[15:0] spectrum_sequence,
 output reg[8:0] dominant_bin,output reg[6:0] peak_height);
 localparam CAPTURE=0,WINDOW_WAIT=1,WINDOW_MUL=2,WINDOW_WRITE=3,
  A_WAIT=4,A_LATCH=5,B_LATCH=6,MUL0=7,MUL1=8,MUL2=9,MUL3=10,
  PRODUCT=11,WRITE_A=12,WRITE_B=13,STEP=14,BIN_WAIT=15,BIN_READ=16,
  BIN_NEXT=17,BAND_WRITE=18,PUBLISH=19,COEFFICIENT_FETCH=21,HISTORY_REQUEST=22,HISTORY_WAIT=23,BAND_PEAK_WRITE=24;
 localparam LEFT=WIDTH-272,BASELINE=HEIGHT-64;
 wire[11:0] dx=x-LEFT;
 wire area=de&&x>=LEFT&&x<LEFT+256&&y>=BASELINE-68&&y<=BASELINE;
 wire[4:0] column=dx[7:3];
 reg[4:0] band;
 reg pending_bank,display_bank;wire[6:0] band_height;
 (* ram_style="bram" *)reg[35:0] data_ram[0:511];
 // One true-dual-port9 RAM combines the immutable quarter-wave table and
 // two display banks. Coefficients occupy0..255, display words256..383.
 (* ram_style="bram" *)reg[8:0] shared_ram[0:1023];
 reg[15:0] initial_coefficients[0:511];integer init_index;
 initial begin
  $readmemh(TWIDDLE_FILE,initial_coefficients);
  for(init_index=0;init_index<1024;init_index=init_index+1)shared_ram[init_index]=0;
  for(init_index=0;init_index<128;init_index=init_index+1)begin
   shared_ram[init_index*2]=initial_coefficients[init_index][8:0];
   shared_ram[init_index*2+1]={2'b00,initial_coefficients[init_index][15:9]};
  end
 end
 reg[4:0] state;reg[8:0] sample_index,read_address,write_address;
 reg write_enable;reg[35:0] write_data,read_data;
 reg[7:0] twiddle_address;
 wire[6:0] sine_address=twiddle_address[7]?-twiddle_address[6:0]:twiddle_address[6:0];
 wire[6:0] cosine_address=twiddle_address[7]?twiddle_address[6:0]:-twiddle_address[6:0];
 wire compute_enable=state==CAPTURE||state==PUBLISH||!area;
 reg[8:0] shared_a_data,shared_b_data;
 reg[15:0] fetched_cosine,fetched_sine;
 reg coefficient_window;
 reg[2:0] request_count,response_count;
 reg request_tag;reg[1:0] response_part;
 reg history_tag,history_available;reg[6:0] history_value,pending_peak_word;
 wire[2:0] fetch_goal=coefficient_window?3'd2:3'd4;
 wire coefficient_request=state==COEFFICIENT_FETCH&&request_count<fetch_goal&&!area;
 wire history_request=state==HISTORY_REQUEST&&!area;
 wire[6:0] quarter_address=request_count[1]?sine_address:cosine_address;
 wire[9:0] display_level_address={3'b010,display_bank,column,1'b0};
 wire[9:0] display_peak_address={3'b010,display_bank,column,1'b1};
 wire[9:0] history_address={3'b010,display_bank,band,1'b1};
 wire[9:0] pending_address={3'b010,pending_bank,band,state==BAND_PEAK_WRITE};
 wire[9:0] shared_a_address=area?display_level_address:history_request?history_address:{2'b00,quarter_address,request_count[0]};
 wire[9:0] shared_b_address=area?display_peak_address:pending_address;
 wire shared_write_enable=rst_n&&!area&&(state==BAND_WRITE||state==BAND_PEAK_WRITE);
 wire[8:0] shared_write_data={2'b00,state==BAND_WRITE?band_height:pending_peak_word};
 wire signed[15:0] positive_cosine=twiddle_address==0?16'sd32767:$signed(fetched_cosine);
 wire signed[15:0] sine_value=twiddle_address==128?16'sd32767:$signed(fetched_sine);
 wire signed[15:0] cosine_coefficient=twiddle_address[7]?-positive_cosine:positive_cosine;
 always @(posedge clk)begin
  shared_a_data<=shared_ram[shared_a_address];
  shared_b_data<=shared_ram[shared_b_address];
  if(shared_write_enable)shared_ram[shared_b_address]<=shared_write_data;
  if(compute_enable)read_data<=data_ram[read_address];
  if(write_enable)data_ram[write_address]<=write_data;
 end
 // A tagged response is captured even if the next pixel takes both read ports.
 // No in-flight coefficient/history response can be lost on a display pause.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   request_count<=0;response_count<=0;request_tag<=0;response_part<=0;
   fetched_cosine<=0;fetched_sine<=0;history_tag<=0;history_available<=0;history_value<=0;
  end else begin
   request_tag<=coefficient_request;response_part<=request_count[1:0];history_tag<=history_request;
   if(state!=COEFFICIENT_FETCH)begin request_count<=0;response_count<=0;end
   else begin
    if(coefficient_request)request_count<=request_count+1'b1;
    if(request_tag)begin
     response_count<=response_count+1'b1;
     case(response_part)
      0:fetched_cosine[8:0]<=shared_a_data;
      1:fetched_cosine[15:9]<=shared_a_data[6:0];
      2:fetched_sine[8:0]<=shared_a_data;
      3:fetched_sine[15:9]<=shared_a_data[6:0];
     endcase
    end
   end
   if(state==HISTORY_REQUEST)history_available<=0;
   if(history_tag)begin history_available<=1;history_value<=shared_a_data[6:0];end
  end
 end
 // synthesis translate_off
 wire[13:0] spectrum_ram[0:63];genvar display_alias;
 generate for(display_alias=0;display_alias<64;display_alias=display_alias+1)begin:simulation_bank_view
  assign spectrum_ram[display_alias]={shared_ram[256+display_alias*2][6:0],shared_ram[257+display_alias*2][6:0]};
 end endgenerate
 always @(posedge clk)if(shared_write_enable&&shared_b_address<256)$fatal(1,"immutable coefficient RAM write");
 // synthesis translate_on
 function[8:0] reverse9;input[8:0] v;integer i;begin for(i=0;i<9;i=i+1)reverse9[i]=v[8-i];end endfunction
 reg signed[17:0] multiply_a,multiply_b;
 reg signed[35:0] multiply_result;
 always @(posedge clk)if(compute_enable)multiply_result<=multiply_a*multiply_b;
 reg signed[17:0] ar,ai,tr,ti;
 wire signed[17:0] br=read_data[35:18],bi=read_data[17:0];
 reg signed[15:0] wr;wire signed[15:0] wi=-sine_value;
 reg signed[35:0] p0,p1,p2;
 reg signed[24:0] sample_sum;
 reg signed[15:0] block_mean;
 wire signed[25:0] sum_next=$signed({sample_sum[24],sample_sum})+$signed({{10{pcm_left[23]}},pcm_left[23:8]});
 reg capture_negative_cos;
 reg[3:0] stage;
 reg[8:0] group_base,j,half_size;
 wire[8:0] butterfly_a=group_base|j,butterfly_b=group_base|j|half_size;
 reg[7:0] twiddle_step;
 reg[8:0] bin_index;
 reg[18:0] band_magnitude,max_magnitude;
 reg[8:0] pending_dominant;
 reg[6:0] pending_peak;
 function[8:0] band_end;input[4:0] b;begin
  if(b<16)band_end={4'd0,b}+9'd2;
  else case(b)
   16:band_end=19;17:band_end=23;18:band_end=27;19:band_end=32;
   20:band_end=38;21:band_end=45;22:band_end=54;23:band_end=64;
   24:band_end=76;25:band_end=91;26:band_end=108;27:band_end=128;
   28:band_end=152;29:band_end=181;30:band_end=215;default:band_end=256;
  endcase
 end endfunction
 // Priority encoding with constant slices avoids a 32-bit barrel shifter.
 // This is bit-for-bit identical to 4*floor(log2(m))+fraction+12, clipped64.
 function[6:0] log_height;input[18:0] magnitude;begin
  if(|magnitude[18:13])log_height=7'd64;
  else casez(magnitude[12:0])
   13'b1????????????:log_height=7'd60+{5'd0,magnitude[11:10]};
   13'b01???????????:log_height=7'd56+{5'd0,magnitude[10:9]};
   13'b001??????????:log_height=7'd52+{5'd0,magnitude[9:8]};
   13'b0001?????????:log_height=7'd48+{5'd0,magnitude[8:7]};
   13'b00001????????:log_height=7'd44+{5'd0,magnitude[7:6]};
   13'b000001???????:log_height=7'd40+{5'd0,magnitude[6:5]};
   13'b0000001??????:log_height=7'd36+{5'd0,magnitude[5:4]};
   13'b00000001?????:log_height=7'd32+{5'd0,magnitude[4:3]};
   13'b000000001????:log_height=7'd28+{5'd0,magnitude[3:2]};
   13'b0000000001???:log_height=7'd24+{5'd0,magnitude[2:1]};
   13'b00000000001??:log_height=7'd20+{5'd0,magnitude[1:0]};
   13'b000000000001?:log_height=7'd16;
   13'b0000000000001:log_height=7'd12;
   default:log_height=0;
  endcase
 end endfunction
 assign band_height=log_height(band_magnitude);
 wire[6:0] previous_peak=ready?history_value:7'd0;
 wire[6:0] next_peak=band_height>previous_peak?band_height:previous_peak==0?7'd0:previous_peak-7'd1;
 wire[8:0] next_j=j+9'd1;
 wire[9:0] next_group={1'b0,group_base}+{half_size,1'b0};
 wire signed[17:0] absolute_factor_re=read_data[35]?-18'sd1:18'sd1;
 wire signed[17:0] absolute_factor_im=read_data[17]?-18'sd1:18'sd1;
 wire signed[35:0] absolute_product_re=$signed(read_data[35:18])*absolute_factor_re;
 wire signed[35:0] absolute_product_im=$signed(read_data[17:0])*absolute_factor_im;
 wire[17:0] absolute_re=absolute_product_re[17:0],absolute_im=absolute_product_im[17:0];
 wire[18:0] bin_magnitude=absolute_re>=absolute_im?{1'b0,absolute_re}+({1'b0,absolute_im}>>1):{1'b0,absolute_im}+({1'b0,absolute_re}>>1);
 wire signed[36:0] real_product=$signed({p0[35],p0})-$signed({p1[35],p1});
 wire signed[36:0] imag_product=$signed({p2[35],p2})+$signed({multiply_result[35],multiply_result});
 wire butterfly_subtract=state==WRITE_B;
 wire[18:0] butterfly_term_re={tr[17],tr}^{19{butterfly_subtract}};
 wire[18:0] butterfly_term_im={ti[17],ti}^{19{butterfly_subtract}};
 wire[18:0] butterfly_result_re={ar[17],ar}+butterfly_term_re+butterfly_subtract;
 wire[18:0] butterfly_result_im={ai[17],ai}+butterfly_term_im+butterfly_subtract;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=CAPTURE;sample_index<=0;read_address<=0;write_address<=0;write_enable<=0;write_data<=0;
   twiddle_address<=0;coefficient_window<=1;pending_peak_word<=0;multiply_a<=0;multiply_b<=0;sample_sum<=0;block_mean<=0;capture_negative_cos<=0;
   ar<=0;ai<=0;tr<=0;ti<=0;wr<=0;p0<=0;p1<=0;p2<=0;
   stage<=0;group_base<=0;j<=0;half_size<=1;twiddle_step<=0;
   band<=0;bin_index<=1;band_magnitude<=0;max_magnitude<=0;pending_dominant<=0;pending_peak<=0;
   pending_bank<=0;display_bank<=1;ready<=0;spectrum_sequence<=0;dominant_bin<=0;peak_height<=0;
  end else begin
   write_enable<=0;
   if(compute_enable)case(state)
    CAPTURE:if(pcm_valid)begin
     write_address<=reverse9(sample_index);write_data<={ {2{pcm_left[23]}},pcm_left[23:8],18'd0};write_enable<=1;
     sample_sum<=sum_next[24:0];
     if(sample_index==511)begin block_mean<=sum_next>>>9;sample_index<=0;read_address<=0;twiddle_address<=0;capture_negative_cos<=0;coefficient_window<=1;state<=COEFFICIENT_FETCH;end
     else sample_index<=sample_index+1'b1;
    end
    COEFFICIENT_FETCH:if(response_count==fetch_goal)state<=coefficient_window?WINDOW_WAIT:A_WAIT;
    WINDOW_WAIT:state<=WINDOW_MUL;
    WINDOW_MUL:begin
     multiply_a<=$signed(read_data[35:18])-$signed({{2{block_mean[15]}},block_mean});
     multiply_b<=(18'sd32767-(capture_negative_cos?-$signed({{2{cosine_coefficient[15]}},cosine_coefficient}):$signed({{2{cosine_coefficient[15]}},cosine_coefficient})))>>>1;
     state<=WINDOW_WRITE;
    end
    WINDOW_WRITE:state<=20;
    20:begin
     write_address<=reverse9(sample_index);write_data<={multiply_result[32:15],18'd0};write_enable<=1;
     if(sample_index==511)begin
      stage<=0;half_size<=1;twiddle_step<=0;group_base<=0;j<=0;
      read_address<=0;twiddle_address<=0;coefficient_window<=0;state<=COEFFICIENT_FETCH;
     end else begin
      sample_index<=sample_index+1'b1;read_address<=reverse9(sample_index+9'd1);
      twiddle_address<=sample_index[7:0]+1'b1;capture_negative_cos<=(sample_index+9'd1)>=256;coefficient_window<=1;state<=COEFFICIENT_FETCH;
     end
    end
    A_WAIT:begin read_address<=butterfly_b;state<=A_LATCH;end
    A_LATCH:begin ar<=read_data[35:18];ai<=read_data[17:0];wr<=cosine_coefficient;state<=B_LATCH;end
    B_LATCH:begin
     multiply_a<=read_data[35:18];multiply_b<={{2{wr[15]}},wr};state<=MUL0;
    end
    MUL0:begin multiply_a<=bi;multiply_b<={{2{wi[15]}},wi};state<=MUL1;end
    MUL1:begin p0<=multiply_result;multiply_a<=br;multiply_b<={{2{wi[15]}},wi};state<=MUL2;end
    MUL2:begin p1<=multiply_result;multiply_a<=bi;multiply_b<={{2{wr[15]}},wr};state<=MUL3;end
    MUL3:begin p2<=multiply_result;state<=PRODUCT;end
    PRODUCT:begin tr<=real_product>>>15;ti<=imag_product>>>15;state<=WRITE_A;end
    WRITE_A:begin write_enable<=1;write_address<=butterfly_a;write_data<={butterfly_result_re[18:1],butterfly_result_im[18:1]};state<=WRITE_B;end
    WRITE_B:begin write_enable<=1;write_address<=butterfly_b;write_data<={butterfly_result_re[18:1],butterfly_result_im[18:1]};state<=STEP;end
    STEP:begin
     if(next_j<half_size)begin
      j<=j+1'b1;
      read_address<=group_base|next_j;twiddle_address<=twiddle_address+twiddle_step;coefficient_window<=0;state<=COEFFICIENT_FETCH;
     end else if(!next_group[9])begin
      group_base<=next_group[8:0];j<=0;
      read_address<=next_group[8:0];twiddle_address<=0;coefficient_window<=0;state<=COEFFICIENT_FETCH;
     end else if(stage!=8)begin
      stage<=stage+1'b1;half_size<=half_size<<1;twiddle_step<=stage==0?8'd128:twiddle_step>>1;group_base<=0;j<=0;
      read_address<=0;twiddle_address<=0;coefficient_window<=0;state<=COEFFICIENT_FETCH;
     end else begin band<=0;bin_index<=1;read_address<=1;band_magnitude<=0;max_magnitude<=0;pending_dominant<=0;pending_peak<=0;state<=BIN_WAIT;end
    end
    BIN_WAIT:state<=BIN_READ;
    BIN_READ:begin
     if(bin_magnitude>band_magnitude)band_magnitude<=bin_magnitude;
     if(bin_magnitude>max_magnitude)begin max_magnitude<=bin_magnitude;pending_dominant<=bin_index;end
     state<=BIN_NEXT;
    end
    BIN_NEXT:if(bin_index+9'd1==band_end(band))state<=HISTORY_REQUEST;
     else begin bin_index<=bin_index+1'b1;read_address<=bin_index+1'b1;state<=BIN_WAIT;end
    HISTORY_REQUEST:state<=HISTORY_WAIT;
    HISTORY_WAIT:if(history_available)state<=BAND_WRITE;
    BAND_WRITE:begin
     pending_peak_word<=next_peak;
     if(band_height>pending_peak)pending_peak<=band_height;
     state<=BAND_PEAK_WRITE;
    end
    BAND_PEAK_WRITE:begin
     if(band==31)state<=PUBLISH;
     else begin band<=band+1'b1;band_magnitude<=0;bin_index<=bin_index+1'b1;read_address<=bin_index+1'b1;state<=BIN_WAIT;end
    end
    PUBLISH:if(frame_start)begin
     display_bank<=display_bank;pending_bank<=display_bank;ready<=1;spectrum_sequence<=spectrum_sequence+1'b1;
     dominant_bin<=pending_dominant;peak_height<=pending_peak;sample_index<=0;sample_sum<=0;state<=CAPTURE;
    end
    default:state<=CAPTURE;
   endcase
  end
 end
 wire[13:0] displayed_band={shared_a_data[6:0],shared_b_data[6:0]};
 reg plot_area,plot_bar,plot_ready,title_delayed,grid_delayed,render_valid;
 reg[6:0] plot_dy;reg[1:0] plot_colour;
 wire[6:0] height=displayed_band[13:7],held_peak=displayed_band[6:0];
 wire fill=plot_ready&&plot_area&&plot_bar&&plot_dy!=0&&plot_dy<=height;
 wire peak=plot_ready&&plot_area&&plot_bar&&held_peak!=0&&plot_dy==held_peak;
 function[14:0] glyph;input[7:0] c;begin
  case(c)
   "0":glyph=15'b111_101_101_101_111;"1":glyph=15'b010_110_010_010_111;
   "2":glyph=15'b110_001_010_100_111;"3":glyph=15'b110_001_010_001_110;
   "4":glyph=15'b101_101_111_001_001;"5":glyph=15'b111_100_110_001_110;
   "6":glyph=15'b011_100_111_101_111;"8":glyph=15'b111_101_111_101_111;
   "S":glyph=15'b011_100_010_001_110;"P":glyph=15'b110_101_110_100_100;
   "E":glyph=15'b111_100_110_100_111;"C":glyph=15'b011_100_100_100_011;
   "T":glyph=15'b111_010_010_010_010;"R":glyph=15'b110_101_110_101_101;
   "U":glyph=15'b101_101_101_101_111;"M":glyph=15'b101_111_111_101_101;
   "H":glyph=15'b101_101_111_101_101;"z":glyph=15'b000_111_010_100_111;
   "k":glyph=15'b100_101_110_101_101;"-":glyph=15'b000_000_111_000_000;
   default:glyph=0;
  endcase
 end endfunction
 function[7:0] title_char;input[2:0] i;begin
  case(i)0:title_char="S";1:title_char="P";2:title_char="E";3:title_char="C";
   4:title_char="T";5:title_char="R";6:title_char="U";default:title_char="M";endcase
 end endfunction
 function dot;input[7:0] c;input[3:0] column;input[3:0] row;reg[14:0] bits;begin
  bits=glyph(c);dot=column<6&&row<10?bits[14-(row>>1)*3-(column>>1)]:1'b0;
 end endfunction
 wire[11:0] title_x=x-LEFT,title_y=y-(BASELINE-88);
 wire title_pixel=de&&x>=LEFT&&x<LEFT+64&&y>=BASELINE-88&&y<BASELINE-78&&dot(title_char(title_x[5:3]),{1'b0,title_x[2:0]},title_y[3:0]);
 reg[7:0] legend_char;reg[11:0] legend_x,axis_y;reg[7:0] axis_char;
 always @*begin
  legend_x=dx;legend_char=0;
  if(dx<40)case(dx[5:3])0:legend_char="1";1,2:legend_char="0";3:legend_char="H";4:legend_char="z";default:;endcase
  else if(dx>=80&&dx<96)begin legend_x=dx-80;legend_char=legend_x[3]?"k":"1";end
  else if(dx>=176&&dx<192)begin legend_x=dx-176;legend_char=legend_x[3]?"k":"5";end
  else if(dx>=232&&dx<256)begin legend_x=dx-232;case(legend_x[4:3])0:legend_char="2";1:legend_char="0";default:legend_char="k";endcase end
  axis_y=y-(BASELINE-68);axis_char=0;
  if(y>=BASELINE-68&&y<BASELINE-58)axis_char=x>=LEFT-8?"0":0;
  else if(y>=BASELINE-48&&y<BASELINE-38)begin axis_y=y-(BASELINE-48);axis_char=x<LEFT-16?"-":x<LEFT-8?"3":"0";end
  else if(y>=BASELINE-28&&y<BASELINE-18)begin axis_y=y-(BASELINE-28);axis_char=x<LEFT-16?"-":x<LEFT-8?"6":"0";end
 end
 wire[11:0] legend_y=y-(BASELINE+8),axis_x=x-(LEFT-24);
 wire legend_pixel=de&&x>=LEFT&&x<LEFT+256&&y>=BASELINE+8&&y<BASELINE+18&&dot(legend_char,{1'b0,legend_x[2:0]},legend_y[3:0]);
 wire axis_pixel=de&&x>=LEFT-24&&x<LEFT&&dot(axis_char,{1'b0,axis_x[2:0]},axis_y[3:0]);
 // Shared BRAM outputs and registered geometry describe the same input pixel.
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin plot_area<=0;plot_bar<=0;plot_ready<=0;title_delayed<=0;grid_delayed<=0;plot_dy<=0;plot_colour<=0;render_valid<=0;end
  else begin
   plot_area<=area;plot_bar<=dx[2:0]<6;plot_ready<=ready;plot_dy<=BASELINE-y;
   title_delayed<=title_pixel;
   grid_delayed<=(area&&(y==BASELINE||y==BASELINE-24||y==BASELINE-44||y==BASELINE-64))||legend_pixel||axis_pixel;
   plot_colour<=y<BASELINE-48?2'd3:y<BASELINE-32?2'd2:y<BASELINE-16?2'd1:2'd0;
   render_valid<=1;
  end
 always @*begin
  trace_pixel=fill||peak||title_delayed;grid_pixel=grid_delayed;
  colour=!render_valid?16'd0:title_delayed?16'hffff:peak?16'hffe0:plot_colour==3?16'hf800:plot_colour==2?16'hffe0:plot_colour==1?16'h07e0:16'h05bf;
 end
endmodule
