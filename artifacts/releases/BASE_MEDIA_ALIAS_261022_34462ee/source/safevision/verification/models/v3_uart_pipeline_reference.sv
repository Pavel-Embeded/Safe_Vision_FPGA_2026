// SYS-domain UART command/response transport. Configuration has a separate
// owner (v3_user_controls); this module owns framing and byte transport only.
// Reply: $C:ACK=HH,XXXXXXXX*HH\r\n (code byte, signed value as 32-bit hex, XOR).
// The 128-entry queue holds the replies to a 1000-byte command burst, even
// when transmit is slower than receive. Any exceeded bound is counted.
module v3_uart_pipeline_reference #(parameter integer CLK_HZ=100000000,BAUD=115200,BOARD_CATALOG=0,TX_PIPELINE=BOARD_CATALOG)(
 input wire clk,rst_n,rxd,output wire txd,
 output wire command_valid,output wire[7:0] command_target,
 output wire[95:0] command_name,output wire signed[31:0] command_value,output wire command_query,
 input wire reply_valid,input wire[7:0] reply_code,input wire signed[31:0] reply_value,
 input wire evt_valid,input wire[7:0] evt_code,input wire[3:0] evt_src,input wire[31:0] evt_ts,
 output wire evt_ready,
 output wire[31:0] parser_rejected,rx_framing,rx_overrun,
 output reg[31:0] reply_dropped,output wire[6:0] catalog_id);
 wire[7:0] byte_rx;wire byte_valid,parse_reply;wire[7:0] parse_code;
 uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx(
 .clk(clk),.rst_n(rst_n),.rxd(rxd),.ready(1'b1),.data(byte_rx),.valid(byte_valid),
 .frame_errors(rx_framing),.overruns(rx_overrun));
 // Default preserves arbitrary-name byte-parser behavior. The board opts
 // into the finite exact-name ROM catalog; its UART divider is >=32.
 generate if(BOARD_CATALOG)begin:g_catalog
 v3_command_parser_catalog #(.TIMEOUT(CLK_HZ/10)) parser(
 .clk(clk),.rst_n(rst_n),.rx_valid(byte_valid),.rx_data(byte_rx),
 .command_valid(command_valid),.target(command_target),.name(command_name),.value(command_value),.query(command_query),
 .reply_valid(parse_reply),.reply_code(parse_code),.rejected(parser_rejected),.catalog_id(catalog_id));
 end else begin:g_generic
 assign catalog_id=7'd0;
 v3_command_parser #(.TIMEOUT(CLK_HZ/10)) parser(
 .clk(clk),.rst_n(rst_n),.rx_valid(byte_valid),.rx_data(byte_rx),
 .command_valid(command_valid),.target(command_target),.name(command_name),.value(command_value),.query(command_query),
 .reply_valid(parse_reply),.reply_code(parse_code),.rejected(parser_rejected));
 end endgenerate
 wire full,empty;wire[48:0] head;wire pop;
 assign evt_ready=!full && !reply_valid && !parse_reply;
 wire event_push=evt_valid && evt_ready;
 wire push=reply_valid || parse_reply || event_push;
 wire[1:0] lost={1'b0,(push && full)}+{1'b0,(reply_valid && parse_reply)};
 sync_fifo #(.W(49),.DEPTH(128),.ALMOST_FULL_TH(120),.ALMOST_EMPTY_TH(1)) replies(
 .clk(clk),.rst_n(rst_n),.wr_en(push),.din(reply_valid?{1'b0,8'd0,reply_code,reply_value}:
    parse_reply?{1'b0,8'd0,parse_code,32'd0}:{1'b1,4'd0,evt_src,evt_code,evt_ts}),
 .full(full),.almost_full(),.rd_en(pop),.dout(head),.empty(empty),.almost_empty(),.data_count());
 reg sending;reg[4:0] position;reg[48:0] payload;reg[7:0] checksum;
 wire tx_ready;reg[7:0] byte_tx;
 // Board timing boundary: BRAM payload -> byte formatter -> register;
 // registered byte -> checksum and serializer. UART busy time hides refill.
 // Two SYS edges are added before each new response; line baud, byte order,
 // checksum,128 replies and event backpressure retain their contracts.
 wire[7:0] byte_stage;wire byte_fresh;
 wire[48:0] packet;
 wire send_valid=sending && (!TX_PIPELINE || byte_fresh);
 wire[7:0] send_data=TX_PIPELINE?byte_stage:byte_tx;
 wire byte_fire=send_valid && tx_ready;
 generate if(TX_PIPELINE)begin:g_tx_pipeline
  (* preserve="true" *) reg[7:0] data_q;reg fresh_q;
  // Four high padding bits are constant in both ACK and event records.
  // Keep45 meaningful bits between the BRAM output and byte formatting.
  (* preserve="true" *) reg[44:0] message_q;
  assign packet={message_q[44],4'd0,message_q[43:0]};
  assign byte_stage=data_q;assign byte_fresh=fresh_q;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin data_q<=0;fresh_q<=0;message_q<=0;end
   else begin data_q<=byte_tx;message_q<={payload[48],payload[43:0]};
    if(!sending || byte_fire)fresh_q<=0;else fresh_q<=1;
   end
  end
 end else begin:g_tx_direct
  assign byte_stage=byte_tx;assign byte_fresh=1'b1;
  assign packet=payload;
 end endgenerate

 assign pop=!sending && !empty;
 function[7:0] hex;input[3:0] nibble;begin case(nibble)
 4'h0:hex=8'h30;
 4'h1:hex=8'h31;
 4'h2:hex=8'h32;
 4'h3:hex=8'h33;
 4'h4:hex=8'h34;
 4'h5:hex=8'h35;
 4'h6:hex=8'h36;
 4'h7:hex=8'h37;
 4'h8:hex=8'h38;
 4'h9:hex=8'h39;
 4'ha:hex=8'h41;
 4'hb:hex=8'h42;
 4'hc:hex=8'h43;
 4'hd:hex=8'h44;
 4'he:hex=8'h45;
 4'hf:hex=8'h46;
 default:hex=nibble<10?48+nibble:55+nibble;
 endcase end endfunction
 reg format_hex;reg[3:0] format_nibble;reg[7:0] format_literal;
 always @*begin
  format_hex=0;format_nibble=0;format_literal=8'h3f;
  if(packet[48])case(position)
   // $C:EVT=SS,CC,TTTTTTTT*HH CR LF
   0:format_literal=36;1:format_literal=67;2:format_literal=58;3:format_literal=69;4:format_literal=86;5:format_literal=84;6:format_literal=61;
   7:begin format_hex=1;format_nibble=packet[47:44];end 8:begin format_hex=1;format_nibble=packet[43:40];end 9:format_literal=44;
   10:begin format_hex=1;format_nibble=packet[39:36];end 11:begin format_hex=1;format_nibble=packet[35:32];end 12:format_literal=44;
   21:format_literal=42;22:begin format_hex=1;format_nibble=checksum[7:4];end 23:begin format_hex=1;format_nibble=checksum[3:0];end 24:format_literal=13;25:format_literal=10;
   13:begin format_hex=1;format_nibble=packet[31:28];end 14:begin format_hex=1;format_nibble=packet[27:24];end
   15:begin format_hex=1;format_nibble=packet[23:20];end 16:begin format_hex=1;format_nibble=packet[19:16];end
   17:begin format_hex=1;format_nibble=packet[15:12];end 18:begin format_hex=1;format_nibble=packet[11:8];end
   19:begin format_hex=1;format_nibble=packet[7:4];end 20:begin format_hex=1;format_nibble=packet[3:0];end
   default:format_literal=8'h3f;
  endcase else case(position)
   0:format_literal=36;1:format_literal=67;2:format_literal=58;3:format_literal=65;4:format_literal=67;5:format_literal=75;6:format_literal=61;
   7:begin format_hex=1;format_nibble=packet[39:36];end 8:begin format_hex=1;format_nibble=packet[35:32];end 9:format_literal=44;
   18:format_literal=42;19:begin format_hex=1;format_nibble=checksum[7:4];end 20:begin format_hex=1;format_nibble=checksum[3:0];end 21:format_literal=13;22:format_literal=10;
   10:begin format_hex=1;format_nibble=packet[31:28];end 11:begin format_hex=1;format_nibble=packet[27:24];end
   12:begin format_hex=1;format_nibble=packet[23:20];end 13:begin format_hex=1;format_nibble=packet[19:16];end
   14:begin format_hex=1;format_nibble=packet[15:12];end 15:begin format_hex=1;format_nibble=packet[11:8];end
   16:begin format_hex=1;format_nibble=packet[7:4];end 17:begin format_hex=1;format_nibble=packet[3:0];end
   default:format_literal=8'h3f;
  endcase
  byte_tx=format_hex?hex(format_nibble):format_literal;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sending<=0;position<=0;payload<=0;checksum<=0;reply_dropped<=0;end
  else begin
   if(lost!=0)reply_dropped<=(reply_dropped>32'hffffffff-lost)?32'hffffffff:reply_dropped+lost;
   if(pop)begin payload<=head;sending<=1;position<=0;checksum<=0;end
   else if(byte_fire)begin
    if(position>=1 && position<=(packet[48]?20:17))checksum<=checksum^send_data;
    if(position==(packet[48]?25:22))begin sending<=0;position<=0;end else position<=position+1'b1;
   end
  end
 end
 uart_tx #(.CLK_FREQ(CLK_HZ),.BAUD(BAUD)) tx(
 .clk(clk),.rst_n(rst_n),.tx_valid(send_valid),.tx_data(send_data),.tx_ready(tx_ready),.txd(txd));
endmodule
