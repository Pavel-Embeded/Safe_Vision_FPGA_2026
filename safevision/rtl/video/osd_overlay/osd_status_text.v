// Same-domain demo status. FSM mode mapping is private to the stage-1 exercise.
// Indices 0..37; text padded to a fixed width for mode strings.
module osd_status_text(input wire [7:0] char_index,
    input wire [1:0] mode, input wire [3:0] fps_tens,fps_ones,
    input wire sd_ok, output reg [7:0] char_code);
    reg [71:0] mode_text;
    always @* begin
        case (mode)
            0: mode_text="IDLE     ";
            1: mode_text="NORMAL   ";
            2: mode_text="WARNING  ";
            3: mode_text="EMERGENCY";
            default: mode_text="?????????";
        endcase
        char_code=8'h20;
        case (char_index)
            0: char_code="S"; 1: char_code="A"; 2: char_code="F"; 3: char_code="E";
            4: char_code="V"; 5: char_code="I"; 6: char_code="S"; 7: char_code="I";
            8: char_code="O"; 9: char_code="N";
            11: char_code="M"; 12: char_code="O"; 13: char_code="D"; 14: char_code="E";
            15: char_code=":";
            16,17,18,19,20,21,22,23,24: char_code=mode_text[(24-char_index)*8 +: 8];
            26: char_code="F"; 27: char_code="P"; 28: char_code="S"; 29: char_code=":";
            30: char_code=(fps_tens<=9)?(8'h30+fps_tens):8'h3f;
            31: char_code=(fps_ones<=9)?(8'h30+fps_ones):8'h3f;
            33: char_code="S"; 34: char_code="D"; 35: char_code=":";
            36: char_code=sd_ok ? "O" : "-";
            37: char_code=sd_ok ? "K" : "-";
            default: char_code=8'h20;
        endcase
    end
endmodule
