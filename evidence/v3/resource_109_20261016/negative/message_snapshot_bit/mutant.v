// SYS-domain UART command/response transport. Configuration has a separate
// owner (v3_user_controls); this module owns framing and byte transport only.
// Reply: $C:ACK=HH,XXXXXXXX*HH\r\n (code byte, signed value as 32-bit hex, XOR).
// The 128-entry queue holds the replies to a 1000-byte command burst, even
// when transmit is slower than receive. Any exceeded bound is counted.
module v3_uart_link #(parameter integer CLK_HZ=100000000,BAUD=115200,BOARD_CATALOG=0,TX_PIPELINE=BOARD_CATALOG)(
 input wire clk,rst_n,rxd,output wire txd,
 output wire command_valid,output wire[7:0] command_target,
 output wire[95:0] command_name,output wire signed[31:0] command_value,output wire command_query,
 input wire reply_valid,input wire[7:0] reply_code,input wire signed[31:0] reply_value,
 input wire evt_valid,input wire[7:0] evt_code,input wire[3:0] evt_src,input wire[31:0] evt_ts,
 output wire evt_ready,
 output wire[31:0] parser_rejected,rx_framing,rx_overrun,
 output reg[31:0] reply_dropped);
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
 .reply_valid(parse_reply),.reply_code(parse_code),.rejected(parser_rejected),.catalog_id());
 end else begin:g_generic
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
   else begin data_q<=byte_tx;message_q<={payload[48],payload[43:0]}^45'd1;
    if(!sending || byte_fire)fresh_q<=0;else fresh_q<=1;
   end
  end
 end else begin:g_tx_direct
  assign byte_stage=byte_tx;assign byte_fresh=1'b1;
  assign packet=payload;
 end endgenerate

 assign pop=!sending && !empty;
 function[7:0] hex;input[3:0] nibble;begin hex=nibble<10?48+nibble:55+nibble;end endfunction
 always @*begin
  if(packet[48])case(position)
   // $C:EVT=SS,CC,TTTTTTTT*HH CR LF
   0:byte_tx=36;1:byte_tx=67;2:byte_tx=58;3:byte_tx=69;4:byte_tx=86;5:byte_tx=84;6:byte_tx=61;
   7:byte_tx=hex(packet[47:44]);8:byte_tx=hex(packet[43:40]);9:byte_tx=44;
   10:byte_tx=hex(packet[39:36]);11:byte_tx=hex(packet[35:32]);12:byte_tx=44;
   21:byte_tx=42;22:byte_tx=hex(checksum[7:4]);23:byte_tx=hex(checksum[3:0]);24:byte_tx=13;25:byte_tx=10;
   13:byte_tx=hex(packet[31:28]);14:byte_tx=hex(packet[27:24]);
   15:byte_tx=hex(packet[23:20]);16:byte_tx=hex(packet[19:16]);
   17:byte_tx=hex(packet[15:12]);18:byte_tx=hex(packet[11:8]);
   19:byte_tx=hex(packet[7:4]);20:byte_tx=hex(packet[3:0]);
   default:byte_tx=8'h3f;
  endcase else case(position)
   0:byte_tx=36;1:byte_tx=67;2:byte_tx=58;3:byte_tx=65;4:byte_tx=67;5:byte_tx=75;6:byte_tx=61;
   7:byte_tx=hex(packet[39:36]);8:byte_tx=hex(packet[35:32]);9:byte_tx=44;
   18:byte_tx=42;19:byte_tx=hex(checksum[7:4]);20:byte_tx=hex(checksum[3:0]);21:byte_tx=13;22:byte_tx=10;
   10:byte_tx=hex(packet[31:28]);11:byte_tx=hex(packet[27:24]);
   12:byte_tx=hex(packet[23:20]);13:byte_tx=hex(packet[19:16]);
   14:byte_tx=hex(packet[15:12]);15:byte_tx=hex(packet[11:8]);
   16:byte_tx=hex(packet[7:4]);17:byte_tx=hex(packet[3:0]);
   default:byte_tx=8'h3f;
  endcase
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
