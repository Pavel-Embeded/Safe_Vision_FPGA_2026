


module v3_audio_priority_serial #(parameter integer RAMP_N=240,FULL_SCALE=256)(
 input wire audio_clk,rst_n,sample_valid,alarm_req,
 input wire[23:0] wav_l,wav_r,tone_l,tone_r,
 output reg[23:0] audio_l,audio_r,output reg audio_valid,output reg[8:0] gain);
 localparam ERR_BITS=(RAMP_N<=1)?1:$clog2(RAMP_N);
 localparam SUM_BITS=(ERR_BITS+1>10)?ERR_BITS+1:10;
 reg[ERR_BITS-1:0] ramp_error;
 wire[SUM_BITS-1:0] ramp_sum={{(SUM_BITS-ERR_BITS){1'b0}},ramp_error}+FULL_SCALE;
 wire[8:0] ramp_step=ramp_sum/RAMP_N;
 wire[8:0] gain_up=({1'b0,gain}+{1'b0,ramp_step}>10'd256)?9'd256:gain+ramp_step;
 wire[8:0] gain_dn=(gain>ramp_step)?gain-ramp_step:9'd0;
 wire[8:0] n_gain=alarm_req?gain_up:gain_dn;
 reg[2:0] state;
 reg[8:0] mix_gain;
 reg signed[24:0] delta_l,delta_r;
 reg signed[23:0] base_l,base_r;
 reg signed[26:0] product,sum;
 reg signed[17:0] multiplier_a;
 wire signed[17:0] multiplier_b=$signed({9'd0,mix_gain});
 always @*begin
  multiplier_a=0;
  case(state)
   1:multiplier_a=$signed({delta_l[24],delta_l[24:8]});
   2:multiplier_a=$signed({10'd0,delta_l[7:0]});
   3:multiplier_a=$signed({delta_r[24],delta_r[24:8]});
   4:multiplier_a=$signed({10'd0,delta_r[7:0]});
   default:multiplier_a=0;
  endcase
 end
 (* dsp_style="yes" *) wire signed[35:0] multiplier_product=multiplier_a*multiplier_b;
 always@(posedge audio_clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;gain<=0;ramp_error<=0;mix_gain<=0;
   delta_l<=0;delta_r<=0;base_l<=0;base_r<=0;product<=0;sum<=0;
   audio_l<=0;audio_r<=0;audio_valid<=0;
  end else begin
   audio_valid<=0;
   case(state)
    0:if(sample_valid)begin
     gain<=n_gain;ramp_error<=ramp_sum%RAMP_N;mix_gain<=n_gain;
     delta_l<=$signed({tone_l[23],tone_l})-$signed({wav_l[23],wav_l});
     delta_r<=$signed({tone_r[23],tone_r})-$signed({wav_r[23],wav_r});
     base_l<=wav_l;base_r<=wav_r;state<=1;
    end
    1:begin product<=multiplier_product[26:0];state<=2;end
    2:begin sum<=base_l+product;product<=multiplier_product[26:0];state<=3;end
    3:begin audio_l<=sum+$signed({19'd0,product[15:8]});product<=multiplier_product[26:0];state<=4;end
    4:begin sum<=base_r+product;product<=multiplier_product[26:0];state<=5;end
    5:begin audio_r<=sum+$signed({19'd0,product[15:8]});audio_valid<=1;state<=0;end
    default:state<=0;
   endcase
  end
 end
 // synthesis translate_off
 initial if(FULL_SCALE!=256||RAMP_N<1)$fatal(1,"invalid crossfade parameters");
 always@(posedge audio_clk)if(rst_n&&sample_valid&&state!=0)$fatal(1,"crossfade sample overrun");
 // synthesis translate_on
endmodule
