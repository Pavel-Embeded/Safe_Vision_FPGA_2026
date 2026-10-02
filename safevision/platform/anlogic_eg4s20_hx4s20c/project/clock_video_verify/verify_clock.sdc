# TD6.2.1 / EG4S20BG256: internal clock STA for clock_video_verify_top.
# This is not a finished board I/O timing constraint set.
# The 50 MHz reference is the single master clock. TD derives generated
# clocks from the actual PLL primitive parameters and clock buffers.
create_clock -name board_clk_50 -period 20.000 -waveform {0.000 10.000} \
    [get_ports {board_clk}]
derive_clocks

# No clock groups, false paths, or exclusive relation: in particular, the
# pixel/serial clocks remain related and timed. The four reset-request inputs,
# board reset and unpinned probe outputs have no external timing budget yet.
# Their I/O paths must be listed as an unverified boundary in the flow report.
