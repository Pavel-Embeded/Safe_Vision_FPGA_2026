`timescale 1ns/1ps
module tb_card_to_display;
    // The entire B storage/media/write chain now shares the target 125MHz
    // memory domain. SPI divider overrides preserve legal SD clock rates.
    tb_card_to_screen #(.ENABLE_DISPLAY(1),.CLK_HZ(125_000_000)) chain();
endmodule
