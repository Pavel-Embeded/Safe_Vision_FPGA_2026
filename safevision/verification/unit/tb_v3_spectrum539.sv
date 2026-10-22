`timescale 1ns/1ps
module tb_v3_spectrum539;
 reg clk=0,rst_n=0,frame_start=0,pcm_valid=0;always #20 clk=~clk;
 reg[23:0] pcm_left=0;reg[11:0] x=0,y=0;reg de=0;
 wire trace_pixel,grid_pixel,ready;wire[15:0] colour,seq;wire[8:0] dominant;wire[6:0] height;
 v3_audio_spectrum dut(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.pcm_valid(pcm_valid),.pcm_left(pcm_left),.x(x),.y(y),.de(de),.trace_pixel(trace_pixel),.grid_pixel(grid_pixel),.colour(colour),.ready(ready),.spectrum_sequence(seq),.dominant_bin(dominant),.peak_height(height));
 reg[15:0] samples[0:9215];reg[35:0] expected[0:9215];reg[8:0] peaks[0:17];
 reg[13:0] immutable[0:31];integer errors=0,comparisons=0,c,i,k,gotr,goti,want_r,want_i;integer volume_high,volume_low;
 integer old_peak,new_level,want_peak,rx,ry,relative,cx;reg[7:0] reference_char;reg expected_dot;reg was_ready;
 function[6:0] reference_height(input[18:0] magnitude);
  integer bit_index,leading,fraction,scaled;begin
   leading=0;for(bit_index=0;bit_index<19;bit_index++)if(magnitude[bit_index])leading=bit_index;
   fraction=leading>=2?(magnitude>>(leading-2))&3:0;scaled=leading*4+fraction+12;
   reference_height=magnitude==0?0:scaled>=64?64:scaled;
  end
 endfunction
 function[14:0] reference_glyph(input[7:0] character);begin
  case(character)
   "0":reference_glyph=15'b111101101101111;"1":reference_glyph=15'b010110010010111;
   "2":reference_glyph=15'b110001010100111;"3":reference_glyph=15'b110001010001110;
   "5":reference_glyph=15'b111100110001110;"6":reference_glyph=15'b011100111101111;
   "S":reference_glyph=15'b011100010001110;"P":reference_glyph=15'b110101110100100;
   "E":reference_glyph=15'b111100110100111;"C":reference_glyph=15'b011100100100011;
   "T":reference_glyph=15'b111010010010010;"R":reference_glyph=15'b110101110101101;
   "U":reference_glyph=15'b101101101101111;"M":reference_glyph=15'b101111111101101;
   "H":reference_glyph=15'b101101111101101;"z":reference_glyph=15'b000111010100111;
   "k":reference_glyph=15'b100101110101101;"-":reference_glyph=15'b000000111000000;
   default:reference_glyph=0;
  endcase
 end endfunction
 function reference_dot(input[7:0] character,input integer horizontal,input integer vertical);
  reg[14:0] bitmap;begin bitmap=reference_glyph(character);
   reference_dot=horizontal>=0&&horizontal<6&&vertical>=0&&vertical<10?bitmap[14-(vertical/2)*3-horizontal/2]:0;
  end
 endfunction
 task check(input bit ok,input string message);begin comparisons++;if(!ok)begin errors++;if(errors<12)$display("[FAIL] %s case%0d bin%0d",message,c,k);end end endtask
 reg stream_enabled=1,feed_case=0;integer sample_phase=0,case_feed_index=0,background_index=0;
 integer stream_cycle=0,previous_sample_cycle=-1,ignored_computation_samples=0,continuous_samples=0;
 always @(negedge clk)begin
  if(!rst_n)begin sample_phase=0;pcm_valid=0;end
  else if(stream_enabled)begin
   sample_phase=sample_phase+48000;pcm_valid=sample_phase>=25000000;
   if(pcm_valid)begin
    sample_phase=sample_phase-25000000;
    if(feed_case)begin pcm_left={samples[c*512+case_feed_index],8'd0};case_feed_index++;end
    else begin pcm_left={background_index[15:0],8'd0};background_index++;end
   end
  end
 end
 always @(posedge clk)begin
  stream_cycle++;
  if(stream_enabled&&rst_n&&pcm_valid)begin
   if(previous_sample_cycle>=0)check(stream_cycle-previous_sample_cycle==520||stream_cycle-previous_sample_cycle==521,"uninterrupted48k valid cadence while observer computes");
   previous_sample_cycle=stream_cycle;continuous_samples++;
   if(dut.state!=0)ignored_computation_samples++;
  end
 end
 reg scan_stress=1; reg monitor_trace,monitor_grid;reg[15:0] monitor_colour;
 integer monitor_dx,monitor_dy,monitor_band,monitor_level,monitor_peak;integer live_pixel_checks=0;
 always @(posedge clk)if(rst_n&&scan_stress&&c<18&&c%2==1&&dut.state!=0&&dut.state!=19)begin
  // Random computing pixels are either within the graph or de=0. Text-region
  // raster is independently checked exhaustively below with exactly one clock.
  monitor_trace=0;monitor_grid=0;
  monitor_colour=y<368?16'hf800:y<384?16'hffe0:y<400?16'h07e0:16'h05bf;
  if(de&&x>=368&&x<624&&y>=348&&y<=416)begin
   monitor_dx=x-368;monitor_dy=416-y;monitor_band=monitor_dx/8;
   monitor_level=dut.spectrum_ram[{dut.display_bank,monitor_band[4:0]}][13:7];
   monitor_peak=dut.spectrum_ram[{dut.display_bank,monitor_band[4:0]}][6:0];
   monitor_trace=ready&&monitor_dx%8<6&&((monitor_dy>0&&monitor_dy<=monitor_level)||(monitor_peak>0&&monitor_dy==monitor_peak));
   monitor_grid=monitor_dy==0||monitor_dy==24||monitor_dy==44||monitor_dy==64;
   if(ready&&monitor_dx%8<6&&monitor_peak>0&&monitor_dy==monitor_peak)monitor_colour=16'hffe0;
  end
  #1;
  check(trace_pixel==monitor_trace&&grid_pixel==monitor_grid&&colour==monitor_colour,"one-clock trace/grid/palette remains exact during random compute pause/resume");
  live_pixel_checks++;
 end
integer scan_x=0,scan_y=0;reg[31:0] noise_state=32'h537a1234;
 integer paused_states[0:31];integer monitored_accepts=0;
 function[8:0] reverse_sample(input[8:0] value);integer j;begin
  for(j=0;j<9;j++)reverse_sample[j]=value[8-j];
 end endfunction
 always @(negedge clk)if(scan_stress)begin
  noise_state={noise_state[30:0],noise_state[31]^noise_state[21]^noise_state[1]^noise_state[0]};
  if(dut.state==0||c%2==0)begin x=scan_x;y=scan_y;de=scan_x<640&&scan_y<480;end
  else if(noise_state[0])begin x=368+noise_state[8:1];y=348+(noise_state[15:9]%69);de=1;end
  else begin x=noise_state[11:0];y=noise_state[23:12];de=0;end
  if(scan_x==799)begin scan_x=0;scan_y=scan_y==524?0:scan_y+1;end else scan_x++;
 end
 always @(posedge clk)if(rst_n&&!dut.compute_enable)paused_states[dut.state]++;
 reg[35:0] arithmetic_read;
 reg[17:0] arithmetic_a,arithmetic_b;reg[4:0] arithmetic_state;
 integer signed_a,signed_b;reg[18:0] arithmetic_expected;
 initial begin
  for(i=0;i<32;i++)paused_states[i]=0;
  $readmemh("spectrum_samples539.mem",samples);$readmemh("spectrum_expected539.mem",expected);$readmemh("spectrum_peaks539.mem",peaks);
  // Exhaustive comparison to the original arithmetic definition, independent
  // of the priority slices in the synthesizable implementation.
  for(i=0;i<524288;i++)check(dut.log_height(i[18:0])==reference_height(i[18:0]),"all19-bit logarithmic height inputs");
  // Exhaust every18-bit signed absolute input, and independent integer
  // addition/subtraction checks including minimum negative input. All work is
  // under reset, before the real continuous PCM/raster end-to-end cases.
  force dut.read_data=arithmetic_read;
  force dut.ar=arithmetic_a;force dut.ai=arithmetic_a;
  force dut.tr=arithmetic_b;force dut.ti=arithmetic_b;
  force dut.state=arithmetic_state;
  arithmetic_b=18'h25379;
  for(i=0;i<262144;i++)begin
   arithmetic_read={i[17:0],i[17:0]};arithmetic_a=i[17:0];
   arithmetic_b={arithmetic_b[16:0],arithmetic_b[17]^arithmetic_b[10]^arithmetic_b[7]^arithmetic_b[0]};
   signed_a=i>=131072?i-262144:i;
   signed_b=arithmetic_b[17]?{14'h3fff,arithmetic_b}:arithmetic_b;
   arithmetic_state=12;arithmetic_expected=signed_a+signed_b;#1;
   check(dut.absolute_re==(signed_a<0?-signed_a:signed_a)&&dut.absolute_im==(signed_a<0?-signed_a:signed_a),"all18-bit signed absolute values incl minimum negative via inferredDSP");
   check(dut.butterfly_result_re==arithmetic_expected&&dut.butterfly_result_im==arithmetic_expected,"shared19-bit signed butterfly add independent integer result");
   arithmetic_state=13;arithmetic_expected=signed_a-signed_b;#1;
   check(dut.butterfly_result_re==arithmetic_expected&&dut.butterfly_result_im==arithmetic_expected,"shared19-bit signed butterfly subtract independent integer result");
  end
  arithmetic_read=0;arithmetic_a=0;arithmetic_b=0;arithmetic_state=0;#1;
  release dut.read_data;release dut.ar;release dut.ai;release dut.tr;release dut.ti;release dut.state;
  repeat(4)@(negedge clk);rst_n=1;
  for(c=0;c<18;c=c+1)begin
   was_ready=ready;
   for(k=0;k<32;k=k+1)immutable[k]=dut.spectrum_ram[{dut.display_bank,k[4:0]}];
   case_feed_index=0;feed_case=1;
   for(i=0;i<512;i=i+1)begin
    // An independent fractional scheduler runs continuously even during
    // transform/publish. The next512 stream words are this reviewed test case.
    do @(posedge clk);while(!pcm_valid);
    check(dut.state==0&&dut.sample_index==i,"every continuous real48k PCM sample accepted in order regardless of raster");
    #1;monitored_accepts++;
    check(dut.write_enable&&dut.write_address==reverse_sample(i[8:0])&&dut.write_data=={ {2{samples[c*512+i][15]}},samples[c*512+i],18'd0},"capture write bus preserves exact sample and address");
    @(posedge clk);#1;
    check(dut.data_ram[reverse_sample(i[8:0])]=={ {2{samples[c*512+i][15]}},samples[c*512+i],18'd0},"captured RAM sample is exact before any windowing");
    for(k=0;k<32;k=k+1)check(dut.spectrum_ram[{dut.display_bank,k[4:0]}]===immutable[k],"display level and peak bank immutable while capturing");
   end
   feed_case=0;
   wait(dut.state==19);@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    gotr=$signed(dut.data_ram[k][35:18]);goti=$signed(dut.data_ram[k][17:0]);want_r=$signed(expected[c*512+k][35:18]);want_i=$signed(expected[c*512+k][17:0]);
    check(gotr-want_r<=12&&gotr-want_r>=-12&&goti-want_i<=12&&goti-want_i>=-12,"all complex FFT bins vs independent numpy transform");
   end
   for(k=0;k<32;k=k+1)check(dut.spectrum_ram[{dut.display_bank,k[4:0]}]===immutable[k],"display level and peak bank immutable while transforming");
   check(seq==c,"no publish before video frame boundary");
   // Publish immediately after a PCM pulse, leaving a full sample period
   // for the next case to select its payload before CAPTURE can accept it.
   do @(negedge clk);while(!pcm_valid);
   @(negedge clk);#1;frame_start=1;@(negedge clk);#1;frame_start=0;check(seq==c+1&&ready,"one frame commit per complete transform");
   for(k=0;k<32;k=k+1)begin
    new_level=dut.spectrum_ram[{dut.display_bank,k[4:0]}][13:7];old_peak=was_ready?immutable[k][6:0]:0;
    want_peak=new_level>old_peak?new_level:old_peak==0?0:old_peak-1;
    check(dut.spectrum_ram[{dut.display_bank,k[4:0]}][6:0]==want_peak,"one-step peak hold and exact decay at frame commit");
   end
   if(c<2)check(height==0&&dominant==0,"silence and pure DC produce empty spectrum");
   else if(c!=16&&c!=17)check(dominant>=peaks[c]-1&&dominant<=peaks[c]+1,"dominant frequency matches independent model");
   if(c==14)volume_high=height;if(c==15)begin volume_low=height;check(volume_high>=volume_low+6,"same frequency becomes lower at lower PCM volume");end
   if(c==5)begin
    scan_stress=0;de=1;
    for(k=0;k<32;k=k+1)begin
     x=368+k*8;y=406;@(negedge clk);
     check(trace_pixel==(dut.spectrum_ram[{dut.display_bank,k[4:0]}][13:7]>=10||dut.spectrum_ram[{dut.display_bank,k[4:0]}][6:0]==10),"rendered bars correspond to actual frequency bands");
     x=374+k*8;@(negedge clk);check(!trace_pixel,"space between frequency bars");
    end de=0;scan_stress=1;
   end
  end
  stream_enabled=0;pcm_valid=0;scan_stress=0;
  // Fixed renderer colours must be from the production constant-blend palette.
  de=1;x=370;y=328;@(negedge clk);check(colour==16'hffff,"spectrum title uses supported white palette colour");
  de=0;x=0;y=350;@(negedge clk);check(colour==16'hf800,"red high-frequency plot colour");
  y=370;@(negedge clk);check(colour==16'hffe0,"yellow plot colour");
  y=390;@(negedge clk);check(colour==16'h07e0,"green plot colour");
  y=410;@(negedge clk);check(colour==16'h05bf,"cyan plot colour");
  // Pixel-by-pixel independent glyph and grid oracle, with exactly one
  // clock from each input coordinate to the checked output pixel.
  de=1;
  for(ry=0;ry<10;ry++)for(rx=0;rx<64;rx++)begin
   case(rx/8)0:reference_char="S";1:reference_char="P";2:reference_char="E";3:reference_char="C";4:reference_char="T";5:reference_char="R";6:reference_char="U";default:reference_char="M";endcase
   x=368+rx;y=328+ry;@(negedge clk);
   expected_dot=reference_dot(reference_char,rx%8,ry);
   check(trace_pixel==expected_dot&&!grid_pixel,"complete SPECTRUM title raster and one-clock interface");
   if(expected_dot)check(colour==16'hffff,"every title pixel is palette white");
  end
  for(ry=0;ry<10;ry++)for(rx=0;rx<256;rx++)begin
   reference_char=0;relative=rx;
   if(rx<40)case(rx/8)0:reference_char="1";1,2:reference_char="0";3:reference_char="H";default:reference_char="z";endcase
   else if(rx>=80&&rx<96)begin relative=rx-80;reference_char=relative<8?"1":"k";end
   else if(rx>=176&&rx<192)begin relative=rx-176;reference_char=relative<8?"5":"k";end
   else if(rx>=232)begin relative=rx-232;case(relative/8)0:reference_char="2";1:reference_char="0";default:reference_char="k";endcase end
   x=368+rx;y=424+ry;@(negedge clk);
   expected_dot=reference_dot(reference_char,relative%8,ry);
   check(grid_pixel==expected_dot&&!trace_pixel,"all100Hz/1k/5k/20k frequency label pixels and spacing");
  end
  for(ry=0;ry<50;ry++)for(rx=0;rx<24;rx++)begin
   reference_char=0;relative=ry;
   if(ry<10)reference_char=rx>=16?"0":0;
   else if(ry>=20&&ry<30)begin relative=ry-20;reference_char=rx<8?"-":rx<16?"3":"0";end
   else if(ry>=40)begin relative=ry-40;reference_char=rx<8?"-":rx<16?"6":"0";end
   x=344+rx;y=348+ry;@(negedge clk);
   expected_dot=reference_dot(reference_char,rx%8,relative);
   check(grid_pixel==expected_dot&&!trace_pixel,"complete0/-30/-60dB axis label raster");
  end
  for(ry=0;ry<=68;ry++)for(rx=0;rx<256;rx++)begin
   k=rx/8;new_level=dut.spectrum_ram[{dut.display_bank,k[4:0]}][13:7];old_peak=dut.spectrum_ram[{dut.display_bank,k[4:0]}][6:0];
   x=368+rx;y=416-ry;@(negedge clk);
   expected_dot=rx%8<6&&((ry>0&&ry<=new_level)||(old_peak>0&&ry==old_peak));
   check(trace_pixel==expected_dot,"all32 frequency bars, held peaks and two-pixel gaps");
   check(grid_pixel==(ry==0||ry==24||ry==44||ry==64),"all horizontal dB grid pixels");
   if(rx%8<6&&old_peak>0&&ry==old_peak)check(colour==16'hffe0,"all held peak pixels are palette yellow");
  end
  // Reset never exposes the uninitialised distributed RAM, including when an
  // earlier completed spectrum and a partial subsequent capture exist.
  rst_n=0;repeat(3)@(negedge clk);rst_n=1;de=1;x=370;y=410;
  repeat(3)@(negedge clk);check(!ready&&!trace_pixel&&seq==0,"reset masks retained display RAM");
  scan_stress=1;
  for(i=0;i<257;i++)begin @(negedge clk);pcm_valid=1;pcm_left={samples[2*512+i],8'd0};@(negedge clk);pcm_valid=0;end
  rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  for(i=0;i<512;i++)begin @(negedge clk);pcm_valid=1;pcm_left={samples[2*512+i],8'd0};@(negedge clk);pcm_valid=0;end
  wait(dut.state==21&&dut.request_tag);@(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  for(i=0;i<512;i++)begin @(negedge clk);pcm_valid=1;pcm_left={samples[2*512+i],8'd0};@(negedge clk);pcm_valid=0;end
  wait(dut.state==23&&dut.history_tag);@(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  for(i=0;i<512;i++)begin @(negedge clk);pcm_valid=1;pcm_left=0;@(negedge clk);pcm_valid=0;end
  wait(dut.state==19);@(negedge clk);frame_start=1;@(negedge clk);frame_start=0;@(negedge clk);
  check(ready&&seq==1&&height==0&&dominant==0&&!trace_pixel,"fresh silence after partial-capture reset has no stale spectrum");
  for(k=0;k<32;k++)check(dut.spectrum_ram[{dut.display_bank,k[4:0]}]==0,"reset restarts all peak histories");
  scan_stress=0;
  check(live_pixel_checks>10000,"many random pixels verified while all compute states pause/resume");
  check(ignored_computation_samples>18&&continuous_samples>9216,"actual PCM valid pulses continue throughout transform and publish");
  check(monitored_accepts==9216,"all18 continuous512-sample blocks captured with no skip/misorder");
  for(i=1;i<=24;i++)if(i!=19)check(paused_states[i]>0,"every processing state survives randomized drawing pause/resume");
  if(errors==0)$display("[PASS]512-point DC-free Hann FFT, all bins vs numpy, exhaustive log map, frequency separation, volume, packed frame banking, peak decay, palette and raster");
  $display("[TB] tb_v3_spectrum539 done, errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000000;$display("[FAIL] timeout errors=1");$finish;end
endmodule
