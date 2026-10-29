
module uart_rx_reference #(parameter integer CLK_HZ=100000000,BAUD=115200)(
 input wire clk,rst_n,rxd,ready,output reg [7:0] data,output reg valid,
 output reg [31:0] frame_errors,overruns);
 (* async_reg="true" *) reg meta,sync;
 reg [31:0] acc;wire [32:0] next_acc={1'b0,acc}+BAUD*16;
 wire tick=next_acc>=CLK_HZ;
 reg [1:0] state;reg [3:0] phase;reg [2:0] bitno;
 reg [7:0] shift;reg [1:0] votes;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin meta<=1;sync<=1;acc<=0;state<=0;phase<=0;bitno<=0;
   shift<=0;votes<=0;data<=0;valid<=0;frame_errors<=0;overruns<=0;end
  else begin
   meta<=rxd;sync<=meta;acc<=tick?next_acc-CLK_HZ:next_acc;
   if(valid && ready)valid<=0;
   if(tick)case(state)
    0:if(!sync)begin state<=1;phase<=0;votes<=0;end
    1:if(phase==7)begin
       if(!sync)begin state<=2;phase<=0;bitno<=0;end else state<=0;
      end else phase<=phase+1'b1;
    2:begin
      phase<=phase+1'b1;
      if(phase==13)votes<={1'b0,sync};
      if(phase==14)votes<=votes+sync;
      if(phase==15)begin
       shift[bitno]<=(votes+{1'b0,sync}>=2);phase<=0;
       if(bitno==7)state<=3;else bitno<=bitno+1'b1;
      end
    end
    3:if(phase==15)begin
       state<=0;phase<=0;
       if(!sync)begin if(frame_errors!=32'hffffffff)frame_errors<=frame_errors+1'b1;end
       else if(valid && !ready)begin if(overruns!=32'hffffffff)overruns<=overruns+1'b1;end
       else begin data<=shift;valid<=1;end
      end else phase<=phase+1'b1;
   endcase
  end
 end
 // synthesis translate_off
 initial if(CLK_HZ<BAUD*32)$fatal(1,"UART RX clock too slow");
 // synthesis translate_on
endmodule
