`timescale 1ns/1ps
module tb_v3_ticker_shared_port;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,fs=0,de=0;reg[11:0] x=0,y=0;
 wire req;wire[8:0] index;wire[7:0] word;
 wire panel,text_pixel,edge_pixel;wire[11:0] position;
 v3_scrolling_ticker #(.EXTERNAL_FONT(1),.MESSAGE_CHARS(16),.PIXEL_LATENCY(5)) ticker(
  .clk(clk),.rst_n(rst),.frame_start(fs),.x(x),.y(y),.de(de),
  .panel_pixel(panel),.text_pixel(text_pixel),.edge_pixel(edge_pixel),.position(position),.frames(),.loops(),
  .font_request(req),.font_index(index),.font_word(word));
 wire ready_a,ready_b;wire[15:0] seq_a,seq_b;wire[8:0] bin_a,bin_b;wire[6:0] peak_a,peak_b;
 reg[7:0] sample_div=0;reg[31:0] sample_number=0;
 wire pcm_valid=sample_div==0&&a.state==a.CAPTURE&&b.state==b.CAPTURE;
 // A deterministic, non-symmetric source exercises every FFT arithmetic path.
 wire signed[23:0] pcm=sample_number[7:0]<128?24'sd1200000:-24'sd1200000;
 always @(posedge clk)if(rst)begin sample_div<=sample_div+1'b1;if(pcm_valid)sample_number<=sample_number+1'b1;end
 v3_audio_spectrum #(.SHARED_TICKER(1),.SHARED_INIT_FILE("v3_spectrum_ticker.mem")) a(
  .clk(clk),.rst_n(rst),.frame_start(fs),.pcm_valid(pcm_valid),.pcm_left(pcm),.x(x),.y(y),.de(de),
  .trace_pixel(),.grid_pixel(),.colour(),.ready(ready_a),.spectrum_sequence(seq_a),.dominant_bin(bin_a),.peak_height(peak_a),
  .font_request(req),.font_index(index),.font_word(word));
 v3_audio_spectrum #(.SHARED_TICKER(0)) b(
  .clk(clk),.rst_n(rst),.frame_start(fs),.pcm_valid(pcm_valid),.pcm_left(pcm),.x(x),.y(y),.de(de),
  .trace_pixel(),.grid_pixel(),.colour(),.ready(ready_b),.spectrum_sequence(seq_b),.dominant_bin(bin_b),.peak_height(peak_b),
  .font_request(1'b0),.font_index(9'd0),.font_word());
 reg pixels[0:4095];reg[15:0] coefficient[0:511];
 reg[4:0] expected_text=0,expected_panel=0,expected_edge=0;
 reg[7:0] expected_word;reg expected_access;
 integer errors=0,comparisons=0,phase,px,py,source_column,i,j,k;
 integer font_reads=0,stalled_band_writes=0,spectrum_checks=0,last_sequence=0;reg[4:0] saved_band_state;reg blocked_before_edge;
 reg[8:0] expected_ram;
 task ck(input bit okay,input string message);begin
  comparisons++;if(!okay)begin errors++;if(errors<15)$display("[FAIL] %s phase=%0d x=%0d y=%0d",message,phase,x,y);end
 end endtask
 always @(posedge clk)if(rst)begin
  expected_access=req;expected_word=0;
  if(req)begin
   font_reads++;
   for(j=0;j<8;j++)expected_word[7-j]=pixels[index[4:1]*256+index[8:5]*16+index[0]*8+j];
   ck(a.shared_b_address==384+index,"shared port selects the exact immutable font address");
  end
  blocked_before_edge=a.font_blocks_write;saved_band_state=a.state;
  if(blocked_before_edge)begin stalled_band_writes++;ck(!a.shared_write_enable,"font lookup defers band writes");end
  #0.001;
  if(blocked_before_edge)ck(a.state===saved_band_state,"font lookup holds only the contested publication state");
  if(expected_access)ck(word===expected_word,"shared font bytes match independent row-major pixels");
  if(ready_a&&ready_b&&seq_a==seq_b&&seq_a!=last_sequence)begin
   spectrum_checks++;last_sequence=seq_a;
   ck(bin_a===bin_b&&peak_a===peak_b,"shared lookup preserves FFT dominant bin and peak");
   for(k=0;k<32;k++)ck(a.spectrum_ram[{a.display_bank,5'(k)}]===b.spectrum_ram[{b.display_bank,5'(k)}],"all32 published levels and held peaks equal the unshared analyzer");
  end
 end
 task pixel(input integer xx,yy,input bit active);reg v,dot;begin
  @(negedge clk);x=xx;y=yy;de=active;fs=0;
  v=active&&xx>=120&&xx<632&&yy>=456&&yy<476;
  source_column=xx-(632-phase);dot=0;
  if(v&&yy>=458&&yy<474&&source_column>=0&&source_column<256)dot=pixels[(yy-458)*256+source_column];
  @(posedge clk);#0.002;
  expected_text={expected_text[3:0],dot};expected_panel={expected_panel[3:0],v};expected_edge={expected_edge[3:0],v&&yy==456};
  ck(text_pixel===expected_text[4]&&panel===expected_panel[4]&&edge_pixel===expected_edge[4],"five-clock Chinese pixels, panel and border align under real FFT arbitration");
 end endtask
 initial begin
  $readmemb("pixels.mem",pixels);$readmemh("v3_spectrum_twiddle.mem",coefficient);
  repeat(5)@(negedge clk);rst=1;
  for(phase=0;phase<768;phase++)begin
   force ticker.position=phase;
   @(negedge clk);fs=1;de=0;@(negedge clk);fs=0;
   for(py=454;py<478;py++)for(px=0;px<800;px++)pixel(px,py,px<640&&px%17!=0);
  end
  $display("[PASS] every reachable scroll position, glyph row, border, blanking and shared-port FFT publication");
  ck(font_reads>100000&&stalled_band_writes>0&&spectrum_checks>5,"substantial font activity, contested writes and completed spectra are covered");
  for(i=0;i<1024;i++)if(i<256||i>=384)begin
   expected_ram=0;
   if(i<256)expected_ram=i%2?{2'b0,coefficient[i/2][15:9]}:coefficient[i/2][8:0];
   if(i>=384&&i<896)begin
    for(j=0;j<8;j++)expected_ram[7-j]=pixels[((i-384)/2%16)*256+((i-384)/32)*16+((i-384)%2)*8+j];
   end
   ck(a.shared_ram[i]===expected_ram,"all immutable coefficients, font words and unused padding survive writes");
  end
  release ticker.position;
  $display("[PASS] immutable combined RAM and all published spectrum words against an unshared analyzer");
  $display("PASS tb_v3_ticker_shared_port errors=%0d comparisons=%0d font_reads=%0d contested=%0d spectra=%0d",errors,comparisons,font_reads,stalled_band_writes,spectrum_checks);$finish;
 end
 initial begin #2000000000;$display("[FAIL] shared-font watchdog errors=1");$finish;end
endmodule
