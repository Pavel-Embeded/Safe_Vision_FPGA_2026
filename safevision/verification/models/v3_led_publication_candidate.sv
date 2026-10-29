module v3_led_publication_candidate(input wire clk,sys_clk,sys_rst_n,ref_rst_n,normal_uart_txd,sys_loss_ref,fatal_uart_txd,safe_active,recovery_busy,transition_busy,cached,output reg uart_txd,output reg[3:0] led);
 reg normal_uart_half;reg led_release_half;


 wire[3:0] status_half=led_release_half?{safe_active,recovery_busy,transition_busy,cached}:4'd0;
 always @(negedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin normal_uart_half<=1'b1;led_release_half<=0;end
  else begin normal_uart_half<=normal_uart_txd;led_release_half<=1;end
 end
 always @(posedge clk or negedge ref_rst_n)begin
  if(!ref_rst_n)begin uart_txd<=1'b1;led<=4'd0;end
  else begin uart_txd<=sys_loss_ref?fatal_uart_txd:normal_uart_half;
   led<=sys_loss_ref?4'hf:status_half;end
 end

endmodule
