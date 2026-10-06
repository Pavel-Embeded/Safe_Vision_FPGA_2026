create_clock -name sys -period 10.000 [get_ports {sys_clk}]
create_clock -name mem -period 8.000 [get_ports {mem_clk}]
create_clock -name pixel -period 39.705882 [get_ports {pixel_clk}]
