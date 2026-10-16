// Exact pre-optimization board query block retained as a reference.
module v3_board_query_reference(input wire sys_clk,sys_rst_n,cmd_valid,
 input wire[7:0] cmd_target,
 input wire[95:0] cmd_name,
 input wire cmd_query,
 input wire[191:0] ref_status_sys,
 input wire[1:0] active_slot,
 input wire[3:0] cache_sys,
 input wire[7:0] generation,
 input wire[31:0] audio_underflows,
 input wire[31:0] video_underflows,
 input wire[7:0] fault_code,
 input wire presentation_fault,
 input wire[47:0] mem_status_sys,
 input wire video_fault,
 input wire[2:0] fault_level,
 input wire[2:0] recovery_state,
 input wire[1:0] recovery_attempts,
 input wire[3:0] audio_fallback,
 input wire[31:0] audio_overflows,
 input wire[15:0] evt_drops,
 input wire[31:0] uart_rejected,
 input wire[31:0] uart_framing,
 input wire[31:0] uart_overrun,
 input wire[31:0] uart_reply_dropped,
 output reg b_reply,
 output reg[7:0] b_reply_code,
 output reg signed[31:0] b_reply_value);
 always @(posedge sys_clk or negedge sys_rst_n)begin
 if(!sys_rst_n)begin b_reply<=0;b_reply_code<=0;b_reply_value<=0;end
 else begin b_reply<=0;
 if(cmd_valid && cmd_target==66)begin b_reply<=1;b_reply_code<=0;b_reply_value<=0;
 if(!cmd_query)b_reply_code<=3;
 else if(cmd_name=="STATUS")b_reply_value<=ref_status_sys[15:12];
 else if(cmd_name=="SLOT")b_reply_value<=active_slot;
 else if(cmd_name=="CACHE")b_reply_value<=cache_sys;
 else if(cmd_name=="GEN")b_reply_value<=generation;
 else if(cmd_name=="UNDERFLOW")b_reply_value<=audio_underflows;
 else if(cmd_name=="VUNDERFLOW")b_reply_value<=video_underflows;
 else if(cmd_name=="FAULT")b_reply_value<=fault_code;
 else if(cmd_name=="PRESENTATION")b_reply_value<=presentation_fault;
 else if(cmd_name=="INTEGRITY")b_reply_value<=mem_status_sys[11] || video_fault;
 else if(cmd_name=="LEVEL")b_reply_value<=fault_level;
 else if(cmd_name=="RECOVERY")b_reply_value<=recovery_state;
 else if(cmd_name=="RETRIES")b_reply_value<=recovery_attempts;
 else if(cmd_name=="REJECTED")b_reply_value<=ref_status_sys[95:80];
 else if(cmd_name=="IDLOW")b_reply_value<=ref_status_sys[159:128];
 else if(cmd_name=="IDHIGH")b_reply_value<=ref_status_sys[191:160];
 else if(cmd_name=="BADERROR")b_reply_value<=ref_status_sys[127:112];
 else if(cmd_name=="BADID")b_reply_value<=ref_status_sys[111:96];
 else if(cmd_name=="WAVFALLBACK")b_reply_value<=audio_fallback;
 else if(cmd_name=="OVERFLOW")b_reply_value<=audio_overflows;
 else if(cmd_name=="EVENTDROP")b_reply_value<=evt_drops;
 else if(cmd_name=="UARTREJECT")b_reply_value<=uart_rejected;
 else if(cmd_name=="UARTFRAME")b_reply_value<=uart_framing;
 else if(cmd_name=="UARTOVERRUN")b_reply_value<=uart_overrun;
 else if(cmd_name=="UARTDROP")b_reply_value<=uart_reply_dropped;
 else b_reply_code<=3;
 end end end
endmodule
