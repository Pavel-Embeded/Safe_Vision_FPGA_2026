`timescale 1ns/1ps
module tb_v3_volume_serial_step349;
 reg clk=0,rst=0;integer errors=0,comparisons=0,r,b,k,trial_ref,rem_ref;
 reg[29:0] word_ref,expected_word;reg[28:0] lower;
 v3_audio_volume dut(.clk(clk),.rst_n(rst),.valid_in(1'b0),.left_in(24'd0),.right_in(24'd0),.volume(7'd70));
 initial begin #1;rst=1;
  for(r=0;r<100;r = r + 1)for(b=0;b<2;b = b + 1)for(k=0;k<64;k = k + 1)begin
   if(k==0)lower=0;else if(k==1)lower={29{1'b1}};
   else if(k==2)lower=29'h15555555;else if(k==3)lower=29'h0aaaaaaa;
   else if(k<33)lower=29'd1<<(k-4);
   else if(k<62)lower=~(29'd1<<(k-33));else lower=29'h10293847^(29'd91231*k);
   word_ref={v_cast_s1(b),lower};trial_ref=r*2+b;
   expected_word=v_cast_u30((word_ref*2)+(trial_ref/100));rem_ref=trial_ref%100;
   dut.active=1;dut.count=5;dut.divide_count=0;dut.product=word_ref;dut.remainder=v_cast_s7(r);
   #1;
   comparisons = comparisons + 1;if(dut.trial!==v_cast_s8(trial_ref))begin errors = errors + 1;if(errors<8)$display("[FAIL] volume trial r%0d b%0d",r,b);end
   comparisons = comparisons + 1;if(dut.quotient_bit!==v_cast_s1(trial_ref/100))begin errors = errors + 1;if(errors<8)$display("[FAIL] volume quotient bit");end
   comparisons = comparisons + 1;if(dut.divided!==expected_word)begin errors = errors + 1;if(errors<8)$display("[FAIL] volume shifted input/quotient wiring");end
   clk=1;#1;
   comparisons = comparisons + 1;if(dut.product!==expected_word)begin errors = errors + 1;if(errors<8)$display("[FAIL] volume product next-state");end
   comparisons = comparisons + 1;if(dut.remainder!==v_cast_s7(rem_ref))begin errors = errors + 1;if(errors<8)$display("[FAIL] volume remainder expected%0d got%0d",rem_ref,dut.remainder);end
   clk=0;#1;
  end
  if(!errors)$display("[PASS] all200 legal restoring-division trial states, both input bits,64 lower-bit patterns including every basis/complement, real HDL next-state");
  $display("[TB] tb_v3_volume_serial_step349 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end

function signed [0:0] v_cast_s1; input signed [0:0] value; begin begin v_cast_s1=value; end  end endfunction
function signed [6:0] v_cast_s7; input signed [6:0] value; begin begin v_cast_s7=value; end  end endfunction
function signed [7:0] v_cast_s8; input signed [7:0] value; begin begin v_cast_s8=value; end  end endfunction
function [29:0] v_cast_u30; input [29:0] value; begin begin v_cast_u30=value; end  end endfunction
endmodule
