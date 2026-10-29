


module v3_audio_volume_reference(input wire clk,rst_n,valid_in,input wire[23:0] left_in,right_in,
 input wire[6:0] volume,output reg valid_out,output reg[23:0] left_out,right_out,
 output wire busy);
 reg[1:0] state;reg[4:0] count;reg[6:0] gain,saved_gain;
 reg sign_current,sign_right,right_phase;reg[23:0] right_magnitude;
 reg[29:0] shift_value,accumulator;reg[6:0] remainder;
 wire[6:0] safe_gain=volume>100 ? 7'd100:volume;
 wire[29:0] multiply_sum=accumulator+(gain[0] ? shift_value:30'd0);
 wire[7:0] trial={remainder,accumulator[29]};
 wire quotient_bit=trial>=100;
 wire[29:0] divided={accumulator[28:0],quotient_bit};
 wire[23:0] result=sign_current ? (~divided[23:0]+24'd1):divided[23:0];
 assign busy=state!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;count<=0;gain<=0;saved_gain<=0;sign_current<=0;sign_right<=0;right_phase<=0;
   right_magnitude<=0;shift_value<=0;accumulator<=0;remainder<=0;valid_out<=0;left_out<=0;right_out<=0;end
  else begin valid_out<=0;
   case(state)
    0:if(valid_in)begin
     if(safe_gain==0||safe_gain==100)begin
      left_out<=safe_gain==0 ? 24'd0:left_in;right_out<=safe_gain==0 ? 24'd0:right_in;valid_out<=1;
     end else begin
      sign_current<=left_in[23];sign_right<=right_in[23];gain<=safe_gain;saved_gain<=safe_gain;right_phase<=0;
      right_magnitude<=right_in[23] ? (~right_in+24'd1):right_in;
      shift_value<={6'd0,left_in[23] ? (~left_in+24'd1):left_in};
      accumulator<=0;count<=0;state<=1;
     end
    end
    1:begin
     accumulator<=multiply_sum;shift_value<=shift_value<<1;gain<=gain>>1;
     if(count==6)begin remainder<=0;count<=0;state<=2;end
     else count<=count+1'b1;
    end
    2:begin
     accumulator<=divided;remainder<=quotient_bit ? trial-8'd100:trial;
     if(count==29)begin
      if(!right_phase)begin
       left_out<=result;right_phase<=1;sign_current<=sign_right;
       shift_value<={6'd0,right_magnitude};accumulator<=0;gain<=saved_gain;count<=0;state<=1;
      end else begin right_out<=result;valid_out<=1;state<=0;end
     end else count<=count+1'b1;
    end
    default:state<=0;
   endcase
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(rst_n&&valid_in&&busy)begin $display("[FAIL] audio volume scheduler overlapped samples"); $finish; end 
 // synthesis translate_on
endmodule
