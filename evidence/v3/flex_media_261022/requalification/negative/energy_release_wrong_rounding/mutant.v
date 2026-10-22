// HANDBOOK_PROFILE: manual pp93-96, pre-volume LEFT PCM, x1.5 display gain.
// N=1024 stereo sample pairs; abs(-32768)=32768 (unsigned 16-bit).
// Block mean absolute energy, 0..100%, fast attack and 1/8 release.
module audio_energy #(parameter integer LOG_N=10,HANDBOOK_PROFILE=0)(input wire clk,rst_n,sample_valid,
 input wire signed [15:0] pcm_l,pcm_r,output reg [6:0] energy,
 output reg update);
 reg [LOG_N-1:0] count;reg [LOG_N+16:0] sum;
 wire [15:0] al=pcm_l[15]?(~pcm_l+16'd1):pcm_l;
 wire [15:0] ar=pcm_r[15]?(~pcm_r+16'd1):pcm_r;
 wire [16:0] mag=HANDBOOK_PROFILE?{1'b0,al}:({1'b0,al}+{1'b0,ar});
 wire [LOG_N+17:0] total={1'b0,sum}+mag;
 wire [LOG_N+24:0] percent=total*7'd100;
 wire [7:0] raw=percent>>(LOG_N+(HANDBOOK_PROFILE?15:16));
 wire[8:0] boosted={1'b0,raw}+{2'b0,raw[7:1]};
 wire [6:0] level=HANDBOOK_PROFILE?((boosted>100)?7'd100:boosted[6:0]):((raw>100)?7'd100:raw[6:0]);
 reg [6:0] delta;
 // Handbook: floor(diff/8), including100->88. A minimum one step
 // below8 avoids a permanently nonzero residual on true silence.
 always @*begin
  delta=HANDBOOK_PROFILE?((energy-level+7'd7)>>3):((energy-level+7'd7)>>3);
  if(HANDBOOK_PROFILE&&energy>level&&delta==0)delta=1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin count<=0;sum<=0;energy<=0;update<=0;end
  else begin update<=0;
   if(sample_valid)begin
    if(&count)begin count<=0;sum<=0;update<=1;
      if(level>=energy)energy<=level;
      else if(level==0 && energy<=1)energy<=0;
      else energy<=energy-delta;
    end else begin count<=count+1'b1;sum<=total;end
   end
  end
 end
endmodule
