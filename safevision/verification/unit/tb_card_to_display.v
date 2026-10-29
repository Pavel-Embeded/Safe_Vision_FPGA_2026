`timescale 1ns/1ps
module tb_card_to_display;


    tb_card_to_screen #(.ENABLE_DISPLAY(1),.CLK_HZ(125_000_000)) chain();
endmodule
