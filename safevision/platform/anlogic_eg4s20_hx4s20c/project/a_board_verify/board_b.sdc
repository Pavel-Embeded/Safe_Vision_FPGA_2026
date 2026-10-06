# 50 MHz board oscillator R7. Derive ALL system/video/serial PLL clocks.
# This is a bring-up constraint, not a complete HDMI output delay budget.
create_clock -name board_clk -period 20.000 -waveform {0 10} [get_ports {clk}]
derive_clocks
# Only the asynchronous push-button reset assertion is exempt. Do not add
# blanket false paths between PLL domains or relax SDRAM AC timing.
set_false_path -from [get_ports {rst_n}]
