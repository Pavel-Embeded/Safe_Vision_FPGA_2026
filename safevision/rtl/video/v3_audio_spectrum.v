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
 (* rom_style="bram" *)reg[31:0] twiddle_rom[0:255];
 initial $readmemh(TWIDDLE_FILE,twiddle_rom);
 reg[4:0] state;reg[8:0] sample_index,read_address,write_address;
 reg write_enable;reg[35:0] write_data,read_data;
 reg[7:0] twiddle_address;reg[31:0] twiddle_data;
 always @(posedge clk)begin
  read_data<=data_ram[read_address];twiddle_data<=twiddle_rom[twiddle_address];
  if(write_enable)data_ram[write_address]<=write_data;
 end
 function[8:0] reverse9;input[8:0] v;integer i;begin for(i=0;i<9;i=i+1)reverse9[i]=v[8-i];end endfunction
 reg signed[17:0] multiply_a,multiply_b;
 reg signed[35:0] multiply_result;
 always @(posedge clk)multiply_result<=multiply_a*multiply_b;
 reg signed[17:0] ar,ai,br,bi,tr,ti;
 reg signed[15:0] wr,wi;
 reg signed[35:0] p0,p1,p2;
 reg signed[24:0] sample_sum;
 reg signed[15:0] block_mean;
 wire signed[25:0] sum_next=$signed({sample_sum[24],sample_sum})+$signed({{10{pcm_left[23]}},pcm_left[23:8]});
 reg capture_negative_cos;
 reg[3:0] stage;
 reg[8:0] group_base,j,half_size,butterfly_a,butterfly_b;
 reg[7:0] twiddle_step;
 reg[4:0] band;
 reg[8:0] bin_index;
 reg[18:0] band_magnitude,max_magnitude;
 reg[8:0] pending_dominant;
 reg[6:0] pending_peak;
 reg pending_bank,display_bank;
 reg[6:0] levels[0:63],peaks[0:31];
 function[8:0] band_end;input[4:0] b;begin
  if(b<16)band_end={4'd0,b}+9'd2;
  else case(b)
   16:band_end=19;17:band_end=23;18:band_end=27;19:band_end=32;
   20:band_end=38;21:band_end=45;22:band_end=54;23:band_end=64;
   24:band_end=76;25:band_end=91;26:band_end=108;27:band_end=128;
   28:band_end=152;29:band_end=181;30:band_end=215;default:band_end=256;
  endcase
 end endfunction
 function[6:0] log_height;input[18:0] magnitude;integer k,leading;reg[2:0] fraction;reg[9:0] scaled;begin
  leading=0;for(k=0;k<19;k=k+1)if(magnitude[k])leading=k;
  fraction=leading>=2?(magnitude>>(leading-2))&3:0;
  scaled=leading*4+fraction+12;
  log_height=magnitude==0?0:scaled>=64?64:scaled[6:0];
 end endfunction
 wire[17:0] absolute_re=read_data[35]?18'd0-read_data[35:18]:read_data[35:18];
 wire[17:0] absolute_im=read_data[17]?18'd0-read_data[17:0]:read_data[17:0];
 wire[18:0] bin_magnitude=absolute_re>=absolute_im?{1'b0,absolute_re}+({1'b0,absolute_im}>>1):{1'b0,absolute_im}+({1'b0,absolute_re}>>1);
 wire signed[36:0] real_product=$signed({p0[35],p0})-$signed({p1[35],p1});
 wire signed[36:0] imag_product=$signed({p2[35],p2})+$signed({multiply_result[35],multiply_result});
 wire signed[18:0] sum_re=$signed({ar[17],ar})+$signed({tr[17],tr});
 wire signed[18:0] sum_im=$signed({ai[17],ai})+$signed({ti[17],ti});
 wire signed[18:0] dif_re=$signed({ar[17],ar})-$signed({tr[17],tr});
 wire signed[18:0] dif_im=$signed({ai[17],ai})-$signed({ti[17],ti});
 integer n;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=CAPTURE;sample_index<=0;read_address<=0;write_address<=0;write_enable<=0;write_data<=0;
   twiddle_address<=0;multiply_a<=0;multiply_b<=0;sample_sum<=0;block_mean<=0;capture_negative_cos<=0;
   ar<=0;ai<=0;br<=0;bi<=0;tr<=0;ti<=0;wr<=0;wi<=0;p0<=0;p1<=0;p2<=0;
   stage<=0;group_base<=0;j<=0;half_size<=1;butterfly_a<=0;butterfly_b<=1;twiddle_step<=0;
   band<=0;bin_index<=1;band_magnitude<=0;max_magnitude<=0;pending_dominant<=0;pending_peak<=0;
   pending_bank<=0;display_bank<=1;ready<=0;spectrum_sequence<=0;dominant_bin<=0;peak_height<=0;
   for(n=0;n<64;n=n+1)levels[n]<=0;
   for(n=0;n<32;n=n+1)peaks[n]<=0;
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
     multiply_b<=(18'sd32767-(capture_negative_cos?-$signed({{2{twiddle_data[31]}},twiddle_data[31:16]}):$signed({{2{twiddle_data[31]}},twiddle_data[31:16]})))>>>1;
     state<=WINDOW_WRITE;
    end
    WINDOW_WRITE:state<=20;
    20:begin
     write_address<=reverse9(sample_index);write_data<={multiply_result[32:15],18'd0};write_enable<=1;
     if(sample_index==511)begin
      stage<=0;half_size<=1;twiddle_step<=0;group_base<=0;j<=0;
      butterfly_a<=0;butterfly_b<=1;read_address<=0;twiddle_address<=0;state<=A_WAIT;
     end else begin
      sample_index<=sample_index+1'b1;read_address<=reverse9(sample_index+9'd1);
      twiddle_address<=sample_index[7:0]+1'b1;capture_negative_cos<=(sample_index+9'd1)>=256;state<=WINDOW_WAIT;
     end
    end
    A_WAIT:begin read_address<=butterfly_b;state<=A_LATCH;end
    A_LATCH:begin ar<=read_data[35:18];ai<=read_data[17:0];wr<=twiddle_data[31:16];wi<=twiddle_data[15:0];state<=B_LATCH;end
    B_LATCH:begin
     br<=read_data[35:18];bi<=read_data[17:0];
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
     if(j+1<half_size)begin
      j<=j+1'b1;butterfly_a<=butterfly_a+1'b1;butterfly_b<=butterfly_b+1'b1;
      read_address<=butterfly_a+1'b1;twiddle_address<=twiddle_address+twiddle_step;state<=A_WAIT;
     end else if({1'b0,group_base}+{half_size,1'b0}<512)begin
      group_base<=group_base+(half_size<<1);j<=0;butterfly_a<=group_base+(half_size<<1);butterfly_b<=group_base+(half_size<<1)+half_size;
      read_address<=group_base+(half_size<<1);twiddle_address<=0;state<=A_WAIT;
     end else if(stage!=8)begin
      stage<=stage+1'b1;half_size<=half_size<<1;twiddle_step<=stage==0?8'd128:twiddle_step>>1;group_base<=0;j<=0;
      butterfly_a<=0;butterfly_b<=half_size<<1;read_address<=0;twiddle_address<=0;state<=A_WAIT;
     end else begin band<=0;bin_index<=1;read_address<=1;band_magnitude<=0;max_magnitude<=0;pending_dominant<=0;pending_peak<=0;state<=BIN_WAIT;end
    end
    BIN_WAIT:state<=BIN_READ;
    BIN_READ:begin
     if(bin_magnitude>band_magnitude)band_magnitude<=bin_magnitude;
     if(bin_magnitude>max_magnitude)begin max_magnitude<=bin_magnitude;pending_dominant<=bin_index;end
     state<=BIN_NEXT;
    end
    BIN_NEXT:if(bin_index+1==band_end(band))state<=BAND_WRITE;
     else begin bin_index<=bin_index+1'b1;read_address<=bin_index+1'b1;state<=BIN_WAIT;end
    BAND_WRITE:begin
     levels[{pending_bank,band}]<=log_height(band_magnitude);
     if(log_height(band_magnitude)>pending_peak)pending_peak<=log_height(band_magnitude);
     if(band==31)state<=PUBLISH;
     else begin band<=band+1'b1;band_magnitude<=0;bin_index<=bin_index+1'b1;read_address<=bin_index+1'b1;state<=BIN_WAIT;end
    end
    PUBLISH:if(frame_start)begin
     display_bank<=pending_bank;pending_bank<=display_bank;ready<=1;spectrum_sequence<=spectrum_sequence+1'b1;
     dominant_bin<=pending_dominant;peak_height<=pending_peak;sample_index<=0;sample_sum<=0;state<=CAPTURE;
     for(n=0;n<32;n=n+1)peaks[n]<=levels[{pending_bank,n[4:0]}]>peaks[n]?levels[{pending_bank,n[4:0]}]:peaks[n]==0?0:peaks[n]-1'b1;
    end
    default:state<=CAPTURE;
   endcase
  end
 end
 localparam LEFT=WIDTH-272,BASELINE=HEIGHT-64;
 wire[11:0] dx=x-LEFT;
 wire area=de&&x>=LEFT&&x<LEFT+256&&y>=BASELINE-68&&y<=BASELINE;
 wire[4:0] column=dx[7:3];
 wire[6:0] height=levels[{display_bank,column}];
 wire fill=ready&&area&&dx[2:0]<6&&y<BASELINE&&y>=BASELINE-height;
 wire peak=ready&&area&&dx[2:0]<6&&peaks[column]!=0&&y==BASELINE-peaks[column];
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin trace_pixel<=0;grid_pixel<=0;colour<=0;end
  else begin
   trace_pixel<=fill||peak;
   grid_pixel<=area&&(y==BASELINE||y==BASELINE-16||y==BASELINE-32||y==BASELINE-48||y==BASELINE-64);
   colour<=peak?16'hffe0:y<BASELINE-48?16'hf97f:y<BASELINE-32?16'h8bff:y<BASELINE-16?16'h05ff:16'h031f;
  end
endmodule
