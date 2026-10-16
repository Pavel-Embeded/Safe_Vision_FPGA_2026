// N=1024 stereo sample pairs; abs(-32768)=32768 (unsigned 16-bit).
// Block mean absolute energy, 0..100%, fast attack and 1/8 release.
module audio_energy #(parameter integer LOG_N=10)(input wire clk,rst_n,sample_valid,
 input wire signed [15:0] pcm_l,pcm_r,output reg [6:0] energy,
 output reg update);
 reg [LOG_N-1:0] count;reg [LOG_N+16:0] sum;
 wire [15:0] al=pcm_l[15]?(~pcm_l+16'd1):pcm_l;
 wire [15:0] ar=pcm_r[15]?(~pcm_r+16'd1):pcm_r;
 wire [16:0] mag={1'b0,al}+{1'b0,ar};
 wire [LOG_N+17:0] total={1'b0,sum}+mag;
 wire [LOG_N+24:0] percent=total*7'd100;
 wire [7:0] raw=percent>>(LOG_N+16);
 wire [6:0] level=(raw>100)?7'd100:raw[6:0];
 reg [6:0] delta;
 always @* delta=(energy-level+7'd7)>>3;
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
