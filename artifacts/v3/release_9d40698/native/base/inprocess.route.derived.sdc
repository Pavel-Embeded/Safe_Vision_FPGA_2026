create_clock -name board_clk -period 20.000 -waveform {0 10} [get_ports {clk}]
derive_clocks
create_generated_clock -name sd_fast -source [get_ports {clk}] -master_clock [get_clocks {board_clk}] -divide_by 4 [get_ports {sd_dclk}]
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
set_multicycle_path -setup -from [get_clocks sd_ident] -to [get_pins {sd_miso_syn_*.ipad}] 250
set_multicycle_path -hold -end -from [get_clocks sd_ident] -to [get_pins {sd_miso_syn_*.ipad}] 249
set_multicycle_path -setup -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_fast] 2
set_multicycle_path -hold -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_fast] 3
set_multicycle_path -setup -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_ident] 250
set_multicycle_path -hold -start -from [get_clocks board_clk] -through [get_ports {sd_mosi}] -to [get_clocks sd_ident] 499
set_max_delay -datapath_only -to [get_ports {uart_txd led* HDMI_DDC_SCL}] 5.000
set_false_path -from [get_ports {rst_n btn_next btn_auto btn_emergency uart_rxd}]
set_false_path -to [get_regs {*req_meta *ack_meta frame_heartbeat_sync/meta pll_loss_sync/meta locks_meta* video/media_m1 video/media_p1 video/safe_p1 video/fault_s1 video/fault_p1 video/present_s1 video/cache/pixel_fault_meta video/cache/*store/done_meta video/cache/*store/fault_meta}]
set_false_path -through [get_nets {control_common_rst_n media_common_rst_n tx_reset}] -to [get_pins {*.sr */*.sr}]
set_max_delay -datapath_only -from [get_regs {ref_status_mailbox/payload*}] -to [get_regs {ref_status_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {mem_status_mailbox/payload*}] -to [get_regs {mem_status_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {hdmi_status_mailbox/payload*}] -to [get_regs {hdmi_status_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {video/config_mailbox/payload*}] -to [get_regs {video/config_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {video/audio_ready_mailbox/payload*}] -to [get_regs {video/audio_ready_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {video/status_mailbox/payload*}] -to [get_regs {video/status_mailbox/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {video/cache/requests/payload*}] -to [get_regs {video/cache/requests/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {video/cache/responses/payload*}] -to [get_regs {video/cache/responses/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/ring_to_ref/payload*}] -to [get_regs {audio/ring_to_ref/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/index_to_sys/payload*}] -to [get_regs {audio/index_to_sys/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/index_to_mem/payload*}] -to [get_regs {audio/index_to_mem/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/commit_to_mem/payload*}] -to [get_regs {audio/commit_to_mem/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/ready_to_sys/payload*}] -to [get_regs {audio/ready_to_sys/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/control_to_audio/payload*}] -to [get_regs {audio/control_to_audio/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {audio/status_to_sys/payload*}] -to [get_regs {audio/status_to_sys/dst_data*}] 8.000
set_max_delay -datapath_only -from [get_regs {*wr_to_rd*primary_addr_gray_reg*}] -to [get_regs {*wr_to_rd*sync_r1*}] 8.000
set_max_delay -datapath_only -from [get_regs {*rd_to_wr*primary_addr_gray_reg*}] -to [get_regs {*rd_to_wr*sync_r1*}] 8.000
set_false_path -to [get_regs {sink/fa_sync[0] sink/td_sync[0] sink/sl_sync[0] sink/sl_sync[1]}]
set_false_path -to [get_regs {player/mr_sync[0] player/fd_sync[0] player/lok_sync[0]}]
