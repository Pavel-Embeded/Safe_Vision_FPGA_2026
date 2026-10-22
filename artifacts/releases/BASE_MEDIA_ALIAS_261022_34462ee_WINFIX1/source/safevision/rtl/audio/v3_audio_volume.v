// Exact PCM24 gain with a shared gain multiplier and narrow serial divider. Public outputs retain
// the original bypass edge, left publication at37 and right/valid at74 clocks.
// Signed magnitude division truncates toward zero; all input, busy, reset and
// output edges remain identical to the frozen original serial implementation.
module v3_audio_volume(input wire clk,rst_n,valid_in,input wire[23:0] left_in,right_in,
 input wire[6:0] volume,output reg valid_out,output reg[23:0] left_out,right_out,
 output wire busy);
 reg active;reg[6:0] count,saved_gain;reg sign_current,sign_right;
 reg[23:0] right_magnitude;reg[29:0] product;reg[6:0] remainder;reg[4:0] divide_count;
 wire[6:0] safe_gain=volume>100?7'd100:volume;
 wire[23:0] magnitude=active?right_magnitude:(left_in[23]?(~left_in+24'd1):left_in);
 wire[6:0] multiplier_gain=active?saved_gain:safe_gain;
 (* dsp_style="yes" *) wire[30:0] multiplied=magnitude*multiplier_gain;
 // Invariant at each division step: remainder<100. The shifted trial
 // is at most199, so one8-bit compare/subtraction is sufficient. Product
 // and quotient share the same30-bit shift register. Thirty exact steps
 // finish before the existing37/74-edge public publication boundaries.
 wire[7:0] trial={remainder,product[29]};
 wire quotient_bit=trial>=8'd100;
 wire[29:0] divided={product[28:0],quotient_bit};
 wire[23:0] quotient=product[23:0];
 wire[23:0] result=sign_current?(~quotient+24'd1):quotient;
 assign busy=active;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;count<=0;saved_gain<=0;sign_current<=0;sign_right<=0;
   right_magnitude<=0;product<=0;remainder<=0;divide_count<=0;valid_out<=0;left_out<=0;right_out<=0;end
  else begin valid_out<=0;
   if(!active)begin
    if(valid_in)begin
     if(safe_gain==0||safe_gain==100)begin
      left_out<=safe_gain==0?24'd0:left_in;right_out<=safe_gain==0?24'd0:right_in;valid_out<=1;
     end else begin
      active<=1;count<=0;saved_gain<=safe_gain;sign_current<=left_in[23];sign_right<=right_in[23];
      right_magnitude<=right_in[23]?(~right_in+24'd1):right_in;product<=multiplied[29:0];remainder<=0;divide_count<=0;
     end
    end
   end else begin
    count<=count+1'b1;
    if(divide_count<30)begin
     product<=divided;remainder<=quotient_bit?trial-8'd100:trial;
     divide_count<=divide_count+1'b1;
    end
    if(count==36)begin left_out<=result;product<=multiplied[29:0];remainder<=0;divide_count<=0;sign_current<=sign_right;end
    if(count==73)begin right_out<=result;valid_out<=1;active<=0;end
   end
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(rst_n&&valid_in&&busy)$fatal(1,"audio volume scheduler overlapped samples");
 // synthesis translate_on
endmodule
