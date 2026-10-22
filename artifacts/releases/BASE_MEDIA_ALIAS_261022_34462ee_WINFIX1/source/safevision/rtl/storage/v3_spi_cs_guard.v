// REF falling-edge CS publication; survives media reset.
// tx_valid AND producer tx_ready must both be gated by cs_ready.
// SPI engine uses raw_cs_n for its own state; only the pad uses cs_n.
// A complete quiet interval is required even when media reset asynchronously
// aborts a high SCLK. The SCLK->quiet reset is subject to ordinary STA.
module v3_spi_cs_guard(input wire ref_clk,ref_rst_n,raw_cs_n,raw_sclk,
 output reg cs_n,output wire cs_ready);
 reg requested_n,low_qualified;
 wire quiet_reset_n=ref_rst_n && !raw_sclk;
 assign cs_ready=(cs_n==raw_cs_n);
 always @(negedge ref_clk or negedge quiet_reset_n)
  if(!quiet_reset_n)low_qualified<=1'b0;else low_qualified<=1'b1;
 always @(negedge ref_clk or negedge ref_rst_n)
  if(!ref_rst_n)begin requested_n<=1'b1;cs_n<=1'b1;end
  else begin requested_n<=raw_cs_n;if(!raw_sclk && low_qualified)cs_n<=requested_n;end
endmodule
