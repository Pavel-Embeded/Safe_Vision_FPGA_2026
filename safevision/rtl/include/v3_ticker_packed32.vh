// Full32-character bitmap, deduplicated and cropped only across zero pixels.
function [17:0] packed_ticker_descriptor;
 input [4:0] index;
 begin case(index)
  5'd0:packed_ticker_descriptor=18'h0002c;
  5'd1:packed_ticker_descriptor=18'h0132c;
  5'd2:packed_ticker_descriptor=18'h0261e;
  5'd3:packed_ticker_descriptor=18'h03c2c;
  5'd4:packed_ticker_descriptor=18'h04f33;
  5'd5:packed_ticker_descriptor=18'h0542c;
  5'd6:packed_ticker_descriptor=18'h0672c;
  5'd7:packed_ticker_descriptor=18'h07a2c;
  5'd8:packed_ticker_descriptor=18'h08d1e;
  5'd9:packed_ticker_descriptor=18'h0a32d;
  5'd10:packed_ticker_descriptor=18'h0b833;
  5'd11:packed_ticker_descriptor=18'h0bd1e;
  5'd12:packed_ticker_descriptor=18'h0d31e;
  5'd13:packed_ticker_descriptor=18'h0e91e;
  5'd14:packed_ticker_descriptor=18'h0ff2c;
  5'd15:packed_ticker_descriptor=18'h1121e;
  5'd16:packed_ticker_descriptor=18'h0b833;
  5'd17:packed_ticker_descriptor=18'h1282c;
  5'd18:packed_ticker_descriptor=18'h13b2c;
  5'd19:packed_ticker_descriptor=18'h14e2c;
  5'd20:packed_ticker_descriptor=18'h1612d;
  5'd21:packed_ticker_descriptor=18'h1762c;
  5'd22:packed_ticker_descriptor=18'h1892c;
  5'd23:packed_ticker_descriptor=18'h19c1d;
  5'd24:packed_ticker_descriptor=18'h1b11e;
  5'd25:packed_ticker_descriptor=18'h0b833;
  5'd26:packed_ticker_descriptor=18'h1c72c;
  5'd27:packed_ticker_descriptor=18'h1da2c;
  5'd28:packed_ticker_descriptor=18'h1ed2c;
  5'd29:packed_ticker_descriptor=18'h2001e;
  5'd30:packed_ticker_descriptor=18'h2162c;
  5'd31:packed_ticker_descriptor=18'h22915;
  default:packed_ticker_descriptor=18'd0;
 endcase end
endfunction
