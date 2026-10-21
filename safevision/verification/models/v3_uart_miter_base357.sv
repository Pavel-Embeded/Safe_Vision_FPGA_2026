module v3_uart_miter_base357 #(parameter integer CLK_HZ=100000000,BAUD=115200,BOARD_CATALOG=0,TX_PIPELINE=BOARD_CATALOG)(
 input wire clk,rst_n,rxd,output wire txd,
 output wire command_valid,output wire[7:0] command_target,
 output wire[95:0] command_name,output wire signed[31:0] command_value,output wire command_query,
 input wire reply_valid,input wire[7:0] reply_code,input wire signed[31:0] reply_value,
 input wire evt_valid,input wire[7:0] evt_code,input wire[3:0] evt_src,input wire[31:0] evt_ts,
 output wire evt_ready,
 output wire[31:0] parser_rejected,rx_framing,rx_overrun,
 output wire[31:0] reply_dropped,output wire[6:0] catalog_id);
integer miter_errors=0,miter_comparisons=0;
wire txd_old;
wire command_valid_old;
wire [7:0] command_target_old;
wire [95:0] command_name_old;
wire [31:0] command_value_old;
wire command_query_old;
wire evt_ready_old;
wire [31:0] parser_rejected_old;
wire [31:0] rx_framing_old;
wire [31:0] rx_overrun_old;
wire [31:0] reply_dropped_old;
wire [6:0] catalog_id_old;
v3_uart_link #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.BOARD_CATALOG(BOARD_CATALOG),.TX_PIPELINE(TX_PIPELINE)) current(
.clk(clk),
.rst_n(rst_n),
.rxd(rxd),
.reply_valid(reply_valid),
.reply_code(reply_code),
.reply_value(reply_value),
.evt_valid(evt_valid),
.evt_code(evt_code),
.evt_src(evt_src),
.evt_ts(evt_ts),
.txd(txd),
.command_valid(command_valid),
.command_target(command_target),
.command_name(command_name),
.command_value(command_value),
.command_query(command_query),
.evt_ready(evt_ready),
.parser_rejected(parser_rejected),
.rx_framing(rx_framing),
.rx_overrun(rx_overrun),
.reply_dropped(reply_dropped),
.catalog_id(catalog_id));
v3_uart_link_control_reference353 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.BOARD_CATALOG(BOARD_CATALOG),.TX_PIPELINE(TX_PIPELINE)) previous(
.clk(clk),
.rst_n(rst_n),
.rxd(rxd),
.reply_valid(reply_valid),
.reply_code(reply_code),
.reply_value(reply_value),
.evt_valid(evt_valid),
.evt_code(evt_code),
.evt_src(evt_src),
.evt_ts(evt_ts),
.txd(txd_old),
.command_valid(command_valid_old),
.command_target(command_target_old),
.command_name(command_name_old),
.command_value(command_value_old),
.command_query(command_query_old),
.evt_ready(evt_ready_old),
.parser_rejected(parser_rejected_old),
.rx_framing(rx_framing_old),
.rx_overrun(rx_overrun_old),
.reply_dropped(reply_dropped_old),
.catalog_id(catalog_id_old));
always@(posedge clk or negedge rst_n)begin #1;miter_comparisons++;
 if({txd,command_valid,command_target,command_name,command_value,command_query,evt_ready,parser_rejected,rx_framing,rx_overrun,reply_dropped,catalog_id}!=={txd_old,command_valid_old,command_target_old,command_name_old,command_value_old,command_query_old,evt_ready_old,parser_rejected_old,rx_framing_old,rx_overrun_old,reply_dropped_old,catalog_id_old})begin miter_errors++;if(miter_errors<9)$display("[FAIL] UART public-pin/edge mismatch time=%0t newTX=%b oldTX=%b",$time,txd,txd_old);end
end
endmodule
