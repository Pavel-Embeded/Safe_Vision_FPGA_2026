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
  BIN_NEXT=17,BAND_WRITE=18,PUBLISH=19;
 (* ram_style="bram" *)reg[35:0] data_ram[0:511];
 // One synchronous ROM port is time-shared by the existing A/B operand
 // read cycles. Only a quarter-wave is stored; +/-1 endpoints are constants.
 (* rom_style="bram" *)reg[15:0] twiddle_rom[0:511];
 initial $readmemh(TWIDDLE_FILE,twiddle_rom);
 reg[4:0] state;reg[8:0] sample_index,read_address,write_address;
 reg write_enable;reg[35:0] write_data,read_data;
 reg[7:0] twiddle_address;
 wire[6:0] sine_address=twiddle_address[7]?-twiddle_address[6:0]:twiddle_address[6:0];
 wire[6:0] cosine_address=twiddle_address[7]?twiddle_address[6:0]:-twiddle_address[6:0];
 wire[6:0] coefficient_address=state>=A_LATCH&&state<=WRITE_B?sine_address:cosine_address;
 reg[15:0] coefficient_data;
 reg sine_endpoint,cosine_endpoint,cosine_negative;
 wire signed[15:0] sine_value=sine_endpoint?16'sd32767:$signed(coefficient_data);
 wire signed[15:0] cosine_value=cosine_endpoint?16'sd32767:$signed(coefficient_data);
 wire signed[15:0] cosine_coefficient=cosine_negative?-cosine_value:cosine_value;
 always @(posedge clk)begin
  read_data<=data_ram[read_address];
  coefficient_data<=twiddle_rom[{2'b00,coefficient_address}];
  sine_endpoint<=twiddle_address==8'd128;
  cosine_endpoint<=twiddle_address==8'd0;
  cosine_negative<=twiddle_address[7];
  if(write_enable)data_ram[write_address]<=write_data;
 end
 function[8:0] reverse9;input[8:0] v;integer i;begin for(i=0;i<9;i=i+1)reverse9[i]=v[8-i];end endfunction
 reg signed[17:0] multiply_a,multiply_b;
 reg signed[35:0] multiply_result;
 always @(posedge clk)multiply_result<=multiply_a*multiply_b;
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
 reg[4:0] band;
 reg[8:0] bin_index;
 reg[18:0] band_magnitude,max_magnitude;
 reg[8:0] pending_dominant;
 reg[6:0] pending_peak;
 reg pending_bank,display_bank;
 // The display reads one packed level/peak word. A separate 32-word history
 // has only the analysis read port, avoiding duplicated 64-word peak RAMs.
 // ready gates uninitialised data until the first complete bank is filled.
 (* ram_style="distributed" *)reg[13:0] spectrum_ram[0:63];
 (* ram_style="distributed" *)reg[6:0] peak_history[0:31];
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
 wire[6:0] band_height=log_height(band_magnitude);
 wire[6:0] previous_peak=ready?peak_history[band]:7'd0;
 wire[6:0] next_peak=band_height>previous_peak?band_height:previous_peak==0?7'd0:previous_peak-7'd1;
 wire[8:0] next_j=j+9'd1;
 wire[9:0] next_group={1'b0,group_base}+{half_size,1'b0};
 wire[17:0] absolute_re=read_data[35]?18'd0-read_data[35:18]:read_data[35:18];
 wire[17:0] absolute_im=read_data[17]?18'd0-read_data[17:0]:read_data[17:0];
 wire[18:0] bin_magnitude=absolute_re>=absolute_im?{1'b0,absolute_re}+({1'b0,absolute_im}>>1):{1'b0,absolute_im}+({1'b0,absolute_re}>>1);
 wire signed[36:0] real_product=$signed({p0[35],p0})-$signed({p1[35],p1});
 wire signed[36:0] imag_product=$signed({p2[35],p2})+$signed({multiply_result[35],multiply_result});
 wire signed[18:0] sum_re=$signed({ar[17],ar})+$signed({tr[17],tr});
 wire signed[18:0] sum_im=$signed({ai[17],ai})+$signed({ti[17],ti});
 wire signed[18:0] dif_re=$signed({ar[17],ar})-$signed({tr[17],tr});
 wire signed[18:0] dif_im=$signed({ai[17],ai})-$signed({ti[17],ti});
 always @(posedge clk)begin
  if(rst_n&&state==BAND_WRITE)begin
   spectrum_ram[{pending_bank,band}]<={band_height,next_peak};
   peak_history[band]<=next_peak;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=CAPTURE;sample_index<=0;read_address<=0;write_address<=0;write_enable<=0;write_data<=0;
   twiddle_address<=0;multiply_a<=0;multiply_b<=0;sample_sum<=0;block_mean<=0;capture_negative_cos<=0;
   ar<=0;ai<=0;tr<=0;ti<=0;wr<=0;p0<=0;p1<=0;p2<=0;
   stage<=0;group_base<=0;j<=0;half_size<=1;twiddle_step<=0;
   band<=0;bin_index<=1;band_magnitude<=0;max_magnitude<=0;pending_dominant<=0;pending_peak<=0;
   pending_bank<=0;display_bank<=1;ready<=0;spectrum_sequence<=0;dominant_bin<=0;peak_height<=0;
  end else begin
   write_enable<=0;
   case(state)
    CAPTURE:if(pcm_valid)begin
     write_address<=reverse9(sample_index);write_data<={ {2{pcm_left[23]}},pcm_left[23:8],18'd0};write_enable<=1;
     sample_sum<=sum_next[24:0];
     if(sample_index==511)begin block_mean<=sum_next>>>9;sample_index<=0;read_address<=0;twiddle_address<=0;capture_negative_cos<=0;state<=WINDOW_WAIT;end
     else sample_index<=sample_index+1'b1;
    end
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
      read_address<=0;twiddle_address<=0;state<=A_WAIT;
     end else begin
      sample_index<=sample_index+1'b1;read_address<=reverse9(sample_index+9'd1);
      twiddle_address<=sample_index[7:0]+1'b1;capture_negative_cos<=(sample_index+9'd1)>=256;state<=WINDOW_WAIT;
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
    WRITE_A:begin write_enable<=1;write_address<=butterfly_a;write_data<={sum_re[18:1],sum_im[18:1]};state<=WRITE_B;end
    WRITE_B:begin write_enable<=1;write_address<=butterfly_b;write_data<={dif_re[18:1],dif_im[18:1]};state<=STEP;end
    STEP:begin
     if(next_j<half_size)begin
      j<=j+1'b1;
      read_address<=group_base|next_j;twiddle_address<=twiddle_address+twiddle_step;state<=A_WAIT;
     end else if(!next_group[9])begin
      group_base<=next_group[8:0];j<=0;
      read_address<=next_group[8:0];twiddle_address<=0;state<=A_WAIT;
     end else if(stage!=8)begin
      stage<=stage+1'b1;half_size<=half_size<<1;twiddle_step<=stage==0?8'd128:twiddle_step>>1;group_base<=0;j<=0;
      read_address<=0;twiddle_address<=0;state<=A_WAIT;
     end else begin band<=0;bin_index<=1;read_address<=1;band_magnitude<=0;max_magnitude<=0;pending_dominant<=0;pending_peak<=0;state<=BIN_WAIT;end
    end
    BIN_WAIT:state<=BIN_READ;
    BIN_READ:begin
     if(bin_magnitude>band_magnitude)band_magnitude<=bin_magnitude;
     if(bin_magnitude>max_magnitude)begin max_magnitude<=bin_magnitude;pending_dominant<=bin_index;end
     state<=BIN_NEXT;
    end
    BIN_NEXT:if(bin_index+9'd1==band_end(band))state<=BAND_WRITE;
     else begin bin_index<=bin_index+1'b1;read_address<=bin_index+1'b1;state<=BIN_WAIT;end
    BAND_WRITE:begin
     if(band_height>pending_peak)pending_peak<=band_height;
     if(band==31)state<=PUBLISH;
     else begin band<=band+1'b1;band_magnitude<=0;bin_index<=bin_index+1'b1;read_address<=bin_index+1'b1;state<=BIN_WAIT;end
    end
    PUBLISH:if(frame_start)begin
     display_bank<=pending_bank;pending_bank<=display_bank;ready<=1;spectrum_sequence<=spectrum_sequence+1'b1;
     dominant_bin<=pending_dominant;peak_height<=pending_peak;sample_index<=0;sample_sum<=0;state<=CAPTURE;
    end
    default:state<=CAPTURE;
   endcase
  end
 end
 localparam LEFT=WIDTH-272,BASELINE=HEIGHT-64;
 wire[11:0] dx=x-LEFT;
 wire area=de&&x>=LEFT&&x<LEFT+256&&y>=BASELINE-68&&y<=BASELINE;
 wire[4:0] column=dx[7:3];
 wire[13:0] displayed_band=spectrum_ram[{display_bank,column}];
 wire[6:0] height=displayed_band[13:7],held_peak=displayed_band[6:0];
 wire fill=ready&&area&&dx[2:0]<6&&y<BASELINE&&y>=BASELINE-height;
 wire peak=ready&&area&&dx[2:0]<6&&held_peak!=0&&y==BASELINE-held_peak;
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
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin trace_pixel<=0;grid_pixel<=0;colour<=0;end
  else begin
   trace_pixel<=fill||peak||title_pixel;
   grid_pixel<=(area&&(y==BASELINE||y==BASELINE-24||y==BASELINE-44||y==BASELINE-64))||legend_pixel||axis_pixel;
   colour<=title_pixel?16'hffff:peak?16'hffe0:y<BASELINE-48?16'hf800:y<BASELINE-32?16'hffe0:y<BASELINE-16?16'h07e0:16'h05bf;
  end
endmodule
