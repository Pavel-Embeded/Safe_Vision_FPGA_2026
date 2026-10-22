// Exact r+ceil(w/3)+partial<LIMIT, with no divider on the FIFO-word path.
module v3_audio_prefill_compare #(parameter integer LIMIT=928)(
 input wire[15:0] ring_level,input wire[9:0] fifo_words,input wire partial,
 output wire fill);
 generate if(LIMIT>0 && LIMIT<=65536)begin:bounded_limit
  localparam integer CW=LIMIT>1?$clog2(LIMIT):1;
  wire[CW-1:0] gap=(LIMIT-1)-ring_level[CW-1:0];
  wire[CW+1:0] max_words={2'b0,gap}+{1'b0,gap,1'b0};
  wire[10:0] queued_words={1'b0,fifo_words}+(partial?11'd0:11'd0);
  assign fill=(ring_level<LIMIT) && (queued_words<=max_words);
 end else begin:generic_limit
  // Retain the original unsigned32-bit parameter behavior outside the bounded
  // ring geometry. The production limit928 selects the short comparison.
  wire[10:0] rounded_words={1'b0,fifo_words}+11'd2;
  wire[8:0] pairs=(rounded_words/3)+partial;
  assign fill=(ring_level+pairs<LIMIT);
 end endgenerate
endmodule
