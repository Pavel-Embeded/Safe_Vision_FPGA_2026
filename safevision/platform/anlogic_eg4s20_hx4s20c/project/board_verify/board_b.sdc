

create_clock -name board_clk -period 20.000 -waveform {0 10} [get_ports {clk}]
derive_clocks


set_false_path -from [get_ports {rst_n}]
