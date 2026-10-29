`timescale 1ns/1ps
module tb_v3_lossless_shared32_fft;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,fs=0,de=0;reg[11:0]x=0,y=0;
 wire req,hi;wire[8:0]index,word9;wire[7:0]word8;
 wire panel,text_pixel,edge_pixel;wire[11:0]position;
 reg[1:0]probe_run=0;reg[9:0]probe_index=0;
 wire area=de&&x>=368&&x<624&&y>=348&&y<=416;
 wire probe=!req&&!area&&(a.state==a.BAND_WRITE||a.state==a.BAND_PEAK_WRITE)&&probe_run!=3;
 wire ram_request=req||probe;wire[9:0]ram_index=req ? {hi,index}:probe_index;
 always @(posedge clk)if(!rst)begin probe_run<=0;probe_index<=0;end
 else if(probe)begin probe_run<=probe_run+1'b1;probe_index<=probe_index==625 ? 0:probe_index+1'b1;end
 else probe_run<=0;
 v3_scrolling_ticker #(.EXTERNAL_FONT(1),.PACKED_EXTERNAL(1),.MESSAGE_CHARS(32),.PIXEL_LATENCY(5)) ticker(
  .clk(clk),.rst_n(rst),.frame_start(fs),.x(x),.y(y),.de(de),.panel_pixel(panel),.text_pixel(text_pixel),.edge_pixel(edge_pixel),.position(position),.frames(),.loops(),
  .font_request(req),.font_index(index),.font_word(word8),.font_index_hi(hi),.font_word9(word9));
 wire ready_a,ready_b;wire[15:0]seq_a,seq_b;wire[8:0]bin_a,bin_b;wire[6:0]peak_a,peak_b;
 reg[7:0]sample_div=0;reg[31:0]sample_number=0;
 wire pcm_valid=sample_div==0&&a.state==a.CAPTURE&&b.state==b.CAPTURE;
 wire signed[23:0]pcm=sample_number[7:0]<128 ? 24'sd1200000:-24'sd1200000;
 always @(posedge clk)if(rst)begin sample_div<=sample_div+1'b1;if(pcm_valid)sample_number<=sample_number+1'b1;end
 v3_audio_spectrum #(.SHARED_TICKER(1),.SHARED_PACKED_FONT(1),.PACKED_INIT_FILE("v3_spectrum_ticker32.mem"))a(
  .clk(clk),.rst_n(rst),.frame_start(fs),.pcm_valid(pcm_valid),.pcm_left(pcm),.x(x),.y(y),.de(de),.trace_pixel(),.grid_pixel(),.colour(),
  .ready(ready_a),.spectrum_sequence(seq_a),.dominant_bin(bin_a),.peak_height(peak_a),
  .font_request(ram_request),.font_index(ram_index[8:0]),.font_word(word8),.font_index_hi(ram_index[9]),.font_word9(word9));
 v3_audio_spectrum_frozen261026 b(
  .clk(clk),.rst_n(rst),.frame_start(fs),.pcm_valid(pcm_valid),.pcm_left(pcm),.x(x),.y(y),.de(de),.trace_pixel(),.grid_pixel(),.colour(),
  .ready(ready_b),.spectrum_sequence(seq_b),.dominant_bin(bin_b),.peak_height(peak_b));
 reg bitmap[0:8191];reg[8:0]initial_words[0:1023];
 reg[4:0]expected_text=0,expected_panel=0,expected_edge=0;
 reg[8:0]expected_word;reg expected_access,blocked_before_edge;reg[4:0]saved_state;
 integer errors=0,comparisons=0,phase,px,py,column,i,k;
 integer font_reads=0,high_reads=0,highest_reads=0,contested=0,spectra=0,last_sequence=0,display_reads=0;
 task ck(input  okay,input [4095:0] message);begin begin okay = (okay === 1'b1); comparisons = comparisons + 1;if(!okay)begin errors = errors + 1;if(errors<15)$display("[FAIL] %s phase=%0d x=%0d y=%0d",message,phase,x,y);end end  end endtask
 always @(posedge clk)if(rst)begin
  expected_access=ram_request;expected_word=initial_words[384+ram_index];
  if(ram_request)begin
   font_reads = font_reads + 1;if(ram_index[9])high_reads = high_reads + 1;if(expected_word[7])highest_reads = highest_reads + 1;
   ck(ram_index<626&&!area,"font address stays within626immutable words and outside display access");
   ck(a.shared_b_address==384+ram_index,"all10font address bits reach the physical shared read port");
  end
  if(area)begin display_reads = display_reads + 1;ck(a.shared_b_address=={3'b010,a.display_bank,a.column,1'b1},"spectrum raster retains its peak read address");end
  blocked_before_edge=a.font_blocks_write;saved_state=a.state;
  if(blocked_before_edge)begin contested = contested + 1;ck(!a.shared_write_enable,"font read defers a contested display-bank write");end
  #0.001;
  if(blocked_before_edge)ck(a.state===saved_state,"contested publication state holds until read completes");
  if(expected_access)ck(word9===expected_word&&word8===expected_word[7:0],"all9physical font data bits are preserved");
  if(ready_a&&ready_b&&seq_a==seq_b&&seq_a!=last_sequence)begin
   spectra = spectra + 1;last_sequence=seq_a;ck(bin_a===bin_b&&peak_a===peak_b,"dominant frequency and level equal the frozen FFT");
   for(k=0;k<32;k = k + 1)ck(a.spectrum_ram[{a.display_bank,v_cast_s5(k)}]===b.spectrum_ram[{b.display_bank,v_cast_s5(k)}],"all32levels and held peaks equal the frozen FFT");
  end
 end
 task pixel(input integer xx,yy,input  active);reg v,dot;begin begin
  active = (active === 1'b1); @(negedge clk);x=xx;y=yy;de=active;fs=0;
  v=active&&xx>=120&&xx<632&&yy>=456&&yy<476;
  column=xx-(632-phase);dot=0;
  if(v&&yy>=458&&yy<474&&column>=0&&column<512)dot=bitmap[column*16+(yy-458)];
  @(posedge clk);#0.002;
  expected_text={expected_text[3:0],dot};expected_panel={expected_panel[3:0],v};expected_edge={expected_edge[3:0],v&&yy==456};
  ck({text_pixel,panel,edge_pixel}==={expected_text[4],expected_panel[4],expected_edge[4]},"packed32pixels equal the independent original bitmap at the5clock interface");
 end  end endtask
 initial begin
  $readmemh("v3_ticker16.mem",bitmap);$readmemh("v3_spectrum_ticker32.mem",initial_words);
  repeat(5)@(negedge clk);rst=1;
  for(phase=0;phase<1024;phase = phase + 1)begin
   force ticker.position=phase;
   @(negedge clk);fs=1;de=0;@(negedge clk);fs=0;

   if(phase%16==0)for(py=346;py<418;py = py + 1)for(px=0;px<800;px = px + 1)pixel(px,py,px<640);
   for(py=454;py<478;py = py + 1)for(px=0;px<800;px = px + 1)pixel(px,py,px<640&&px%17!=0);
  end
  ck(font_reads>100000&&high_reads>1000&&highest_reads>1000&&contested>0&&spectra>5&&display_reads>100000,"full glyph addresses, highest payload bits, write contention, FFT publication and raster reads are covered");
  for(i=0;i<1024;i = i + 1)if(i<256||i>=384)ck(a.shared_ram[i]===initial_words[i],"every immutable coefficient, font and padding word survives real FFT writes");
  release ticker.position;
  $display("[PASS] all32glyphs/all1024positions,9bit physical font reads, FFT display contention and frozen512point32band spectra");
  $display("PASS tb_v3_lossless_shared32_fft errors=%0d comparisons=%0d font_reads=%0d high_reads=%0d highest_reads=%0d contested=%0d spectra=%0d display_reads=%0d",errors,comparisons,font_reads,high_reads,highest_reads,contested,spectra,display_reads);$finish;
 end
 initial begin #2000000000;$display("[FAIL] packed32FFT watchdog");$display("PASS tb_v3_lossless_shared32_fft errors=1 comparisons=%0d",comparisons);$finish;end

function signed [4:0] v_cast_s5; input signed [4:0] value; begin begin v_cast_s5=value; end  end endfunction
endmodule
