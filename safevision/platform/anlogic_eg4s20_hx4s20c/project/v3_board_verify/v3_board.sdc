

create_clock -name board_clk -period 20.000 -waveform {0 10} [get_ports {clk}]
derive_clocks


create_generated_clock -name sd_fast -source [get_ports {clk}] -master_clock [get_clocks {board_clk}] -divide_by 2 [get_ports {sd_dclk}]
create_generated_clock -name sd_ident -source [get_ports {clk}] -master_clock [get_clocks {board_clk}] -divide_by 500 -add [get_ports {sd_dclk}]


set_input_delay -clock [get_clocks sd_fast] -clock_fall -max 18.000 [get_ports {sd_miso}]
set_input_delay -clock [get_clocks sd_fast] -clock_fall -min 0.000 [get_ports {sd_miso}]
set_input_delay -clock [get_clocks sd_ident] -clock_fall -max 54.000 -add_delay [get_ports {sd_miso}]
set_input_delay -clock [get_clocks sd_ident] -clock_fall -min 0.000 -add_delay [get_ports {sd_miso}]


set_input_delay -clock [get_clocks sd_fast] -max 18.000 -add_delay [get_ports {sd_miso}]
set_input_delay -clock [get_clocks sd_fast] -min 0.000 -add_delay [get_ports {sd_miso}]
set_input_delay -clock [get_clocks sd_ident] -max 54.000 -add_delay [get_ports {sd_miso}]
set_input_delay -clock [get_clocks sd_ident] -min 0.000 -add_delay [get_ports {sd_miso}]
set_output_delay -clock [get_clocks sd_fast] -max 7.000 [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock [get_clocks sd_fast] -min -7.000 [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock [get_clocks sd_ident] -max 7.000 -add_delay [get_ports {sd_mosi sd_ncs}]
set_output_delay -clock [get_clocks sd_ident] -min -7.000 -add_delay [get_ports {sd_mosi sd_ncs}]


set_multicycle_path -setup -from [get_clocks sd_fast] -to [get_pins {sd_miso_syn_*.ipad}] 2
set_multicycle_path -hold -end -from [get_clocks sd_fast] -to [get_pins {sd_miso_syn_*.ipad}] 1
set_multicycle_path -setup -from [get_clocks sd_ident] -to [get_pins {sd_miso_syn_*.ipad}] 251
set_multicycle_path -hold -end -from [get_clocks sd_ident] -to [get_pins {sd_miso_syn_*.ipad}] 250


set_multicycle_path -setup -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_fast] 1
set_multicycle_path -hold -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_fast] 1
set_multicycle_path -setup -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_ident] 250
set_multicycle_path -hold -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_ident] 499


set_max_delay -datapath_only -to [get_ports {uart_txd led* HDMI_DDC_SCL}] 5.000


set_false_path -from [get_ports {rst_n btn_next btn_auto btn_emergency uart_rxd}]


