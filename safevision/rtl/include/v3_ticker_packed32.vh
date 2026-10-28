// Full32-character bitmap, deduplicated and cropped only across zero pixels.
function [17:0] packed_ticker_descriptor;
 input [4:0] index;
 begin case(index)
  5'd0:packed_ticker_descriptor=18'h0002c;
  5'd1:packed_ticker_descriptor=18'h0152c;
  5'd2:packed_ticker_descriptor=18'h02a1e;
  5'd3:packed_ticker_descriptor=18'h0432c;
  5'd4:packed_ticker_descriptor=18'h05833;
  5'd5:packed_ticker_descriptor=18'h05e2c;
  5'd6:packed_ticker_descriptor=18'h0732c;
  5'd7:packed_ticker_descriptor=18'h0882c;
  5'd8:packed_ticker_descriptor=18'h09d1e;
  5'd9:packed_ticker_descriptor=18'h0b62d;
  5'd10:packed_ticker_descriptor=18'h0cd33;
  5'd11:packed_ticker_descriptor=18'h0d31e;
  5'd12:packed_ticker_descriptor=18'h0ec1e;
  5'd13:packed_ticker_descriptor=18'h1051e;
  5'd14:packed_ticker_descriptor=18'h11e2c;
  5'd15:packed_ticker_descriptor=18'h1331e;
  5'd16:packed_ticker_descriptor=18'h0cd33;
  5'd17:packed_ticker_descriptor=18'h14c2c;
  5'd18:packed_ticker_descriptor=18'h1612c;
  5'd19:packed_ticker_descriptor=18'h1762c;
  5'd20:packed_ticker_descriptor=18'h18b2d;
  5'd21:packed_ticker_descriptor=18'h1a22c;
  5'd22:packed_ticker_descriptor=18'h1b72c;
  5'd23:packed_ticker_descriptor=18'h1cc1d;
  5'd24:packed_ticker_descriptor=18'h1e31e;
  5'd25:packed_ticker_descriptor=18'h0cd33;
  5'd26:packed_ticker_descriptor=18'h1fc2c;
  5'd27:packed_ticker_descriptor=18'h2112c;
  5'd28:packed_ticker_descriptor=18'h2262c;
  5'd29:packed_ticker_descriptor=18'h23b1e;
  5'd30:packed_ticker_descriptor=18'h2542c;
  5'd31:packed_ticker_descriptor=18'h26915;
  default:packed_ticker_descriptor=18'd0;
 endcase end
endfunction
