


create_clock -name board_clk_50 -period 20.000 -waveform {0.000 10.000} \
    [get_ports {board_clk}]
derive_clocks


