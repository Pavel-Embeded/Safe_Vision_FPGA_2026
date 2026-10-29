`timescale 1ns/1ps
module tb_v3_registered_recovery_reset;
 reg clk=0,rst=0,request=0,done=0,failed=0,fatal=0;always #5 clk=~clk;
 wire ab,ar,as_,ac,al,bb,br,bs,bc,bl;wire[1:0]aa,ba;wire[2:0]ast,bst;
 media_recovery_ctrl #(.RESET_CYCLES(3),.SETTLE_CYCLES(5),.TIMEOUT_CYCLES(17)) a(clk,rst,request,done,failed,fatal,ab,ar,as_,ac,al,aa,ast);
 v3_recovery_reset_reference #(.RESET_CYCLES(3),.SETTLE_CYCLES(5),.TIMEOUT_CYCLES(17)) b(clk,rst,request,done,failed,fatal,bb,br,bs,bc,bl,ba,bst);
 integer errors=0,comparisons=0,k;reg[31:0]rng=32'hff261801;realtime last_clk=0,last_reset=0;integer skew_checks=0;
 always@(posedge clk)last_clk=$realtime;always@(negedge rst)last_reset=$realtime;
 always@(ar)if($realtime>20)begin comparisons++;if($realtime!=last_clk&&$realtime!=last_reset)begin errors++;$display("[FAIL] media reset changed away from a registered boundary");end end
 always@(posedge clk)begin #0.001;if(rst)begin comparisons++;
 if({ab,ar,as_,ac,al,aa,ast}!=={bb,br,bs,bc,bl,ba,bst})begin errors++;if(errors<12)$display("[FAIL] recovery request/fatal/retry/reset/ack cycle contract");end end end


 always@(posedge clk)if(rst&&a.state==3&&skew_checks==0)begin
  #0.2;force a.state=3'd3;#0.2;force a.state=3'd1;
  #0.2;force a.state=3'd4;#0.2;release a.state;skew_checks++;
 end
 initial begin repeat(4)@(negedge clk);rst=1;
 for(k=0;k<600000;k++)begin
  rng=rng*1664525+1013904223;request=rng[3:0]==0;done=rng[7:4]==0;failed=rng[12:8]==0;fatal=rng[20:13]==0;
  rst=k%1009!=0;@(negedge clk);
 end
 if(skew_checks!=1)begin errors++;$display("[FAIL] recovery transition skew not exercised");end
 if(errors==0)$display("[PASS] registered reset has exact original recovery/reset/retry/fatal edge contract and no off-edge output transition");
 $display("[TB] tb_v3_registered_recovery_reset done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
endmodule
