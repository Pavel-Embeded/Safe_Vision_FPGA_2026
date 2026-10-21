// Stage-6 coordinate label: X:hhh Y:hhh (12-bit hexadecimal, 11 cells).
// Display the configured text origin, stable during a frame.
module osd_coordinate_text(input wire [7:0] char_index,
    input wire [11:0] x_value,y_value,output reg [7:0] char_code);
    function [7:0] hex_digit;
        input [3:0] digit;
        begin hex_digit=(digit<10)?(8'h30+digit):(8'h41+digit-10);end
    endfunction
    always @* begin
        char_code=" ";
        case(char_index)
            0:char_code="X";1:char_code=":";
            2:char_code=hex_digit(x_value[11:8]);3:char_code=hex_digit(x_value[7:4]);4:char_code=hex_digit(x_value[3:0]);
            6:char_code="Y";7:char_code=":";
            8:char_code=hex_digit(y_value[11:8]);9:char_code=hex_digit(y_value[7:4]);10:char_code=hex_digit(y_value[3:0]);
            default:char_code=" ";
        endcase
    end
endmodule
