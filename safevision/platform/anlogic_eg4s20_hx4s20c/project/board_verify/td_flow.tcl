# TD6.2.168116 board bring-up: synthesize/place/route/STA with real pins.
# Target: safevision_top on HX4S20C, HDMI B output, package-in SDRAM.
# No bitgen here. Program hardware only after this passes AND the pin audit
# in docs is reviewed: HDMI TMDS polarity/negative-ball mapping and the
# SDRAM AC path are not proven by this flow alone.
if {![info exists board_mode] || $board_mode ni {base hd}} {error "Select base or hd"}
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set root [file normalize $::env(SAFEVISION_REPO)]}
set platform [file join $root safevision platform anlogic_eg4s20_hx4s20c]
set vend [file join $root 7_lab_ex_2026_nosoft example lab_ex4_tf src user_source hdl_source]
if {[info exists ::env(SAFEVISION_HDMI_VENDOR)]} {set vend [file normalize $::env(SAFEVISION_HDMI_VENDOR)]}
set out [file join $root safevision build out board_verify $board_mode]
if {[info exists ::env(SAFEVISION_BOARD_OUT)]} {set out [file join [file normalize $::env(SAFEVISION_BOARD_OUT)] $board_mode]}
file mkdir $out
file copy -force [file join $root safevision assets fonts font8x16.mem] [file join $out font8x16.mem]
cd $out

set hd [expr {$board_mode eq "hd"}]
set video_pll [expr {$hd ? "sv_video_hd_pll.v" : "sv_video_vga_pll.v"}]

set paths [list \
    [file join $platform rtl safevision_top safevision_top.v] \
    [file join $platform rtl clock reset_sync.v] \
    [file join $platform rtl sdram_app_adapter.v] \
    [file join $platform ip pll sv_system_pll.v] \
    [file join $platform ip pll $video_pll] \
    [file join $platform ip sdram global_def.v] \
    [file join $platform ip sdram sdr_as_ram.enc.v] \
    [file join $platform ip sdram sdr_init_ref.enc.v] \
    [file join $platform ip sdram sdr_wrrd.enc.v] \
    [file join $platform ip sdram sdram.v] \
    [file join $platform ip a_pixel_fifo a_pixel_fifo_ip.v] \
    [file join $platform ip a_pixel_fifo a_pixel_fifo_eram.v] \
    [file join $platform rtl pixel_fifo a_pixel_fifo.v] \
    [file join $platform rtl bmp_frame_sink.v] \
    [file join $vend hdmi_phy_warpper.v] \
    [file join $vend lane_lvds_10_1.v] \
    [file join $vend hdmi1.4b_transmitter_core hdmi_1_4b_transmitter_core_wrapper.enc.v]]
foreach p {rtl/video/frame_reader/pixel_word_packer.v rtl/video/frame_reader/frame_slot_commit.v
           rtl/video/frame_reader/frame_reader.v rtl/video/frame_reader/a_frame_fetch_bridge.v
           rtl/video/video_pipeline/a_video_display_core.v rtl/video/video_pipeline/video_pipeline.v
           rtl/video/video_cdc/video_cdc_mailbox.v rtl/video/video_cdc/video_level_sync.v
           rtl/video/video_compositor/video_layer_delay.v rtl/video/video_compositor/video_compositor.v
           rtl/video/osd_overlay/osd_text_layer.v rtl/video/osd_overlay/osd_status_text.v
           rtl/video/graphics_rom/font8x16_rom.v rtl/video/video_timing/video_timing.v
           rtl/memory/video_read_dma.v rtl/memory/frame_swap_cdc.v rtl/memory/memory_arbiter.v
           rtl/memory/frame_swap_ctrl.v rtl/memory/frame_writer.v rtl/memory/frame_address_gen.v
           rtl/memory/mem_ctrl.v rtl/common/crc16_ccitt.v
           rtl/common/crc7.v rtl/common/uart_tx.v
           rtl/storage/spi_master.v rtl/storage/sd_initializer.v rtl/storage/sd_sector_reader.v
           rtl/storage/mbr_parser.v rtl/storage/fat32_boot_parser.v
           rtl/storage/fat32_directory_scanner.v rtl/storage/fat32_cluster_walker.v
           rtl/storage/file_index.v rtl/storage/file_streamer.v rtl/storage/sd_bmp_player.v
           rtl/media/bmp_parser.v rtl/media/bmp_unpack.v
           rtl/top/safevision_core/safevision_core.v rtl/top/safevision_core/bmp_frame_write_bridge.v} {
    lappend paths [file join $root safevision $p]
}
foreach f $paths {if {![file isfile $f]} {error "Missing source: $f"}}

if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    # read_hdl takes ONE include directory here (a Tcl list shifts the arguments
    # and silently blanks -include_dir). The vendor encrypted HDMI/SDRAM cores
    # resolve their own "global_def.v" from the directory that also holds the
    # .enc.v files, which is why ip/sdram/ and the vendor include/ dir need no
    # extra -include_dir entry.
    read_hdl -file [join $paths " "] \
        -include_dir [file join $root safevision rtl include] \
        -define "SAFEVISION_BOARD_HD=$hd" -top safevision_top
    read_adc [file join $here board_b.adc]
    optimize_rtl
    report_area -file rtl.area
    read_sdc [file join $here board_b.sdc]
    read_sdc [file join $here board_cdc.sdc]
    optimize_gate
    legalize_phy_inst
    read_sdc [file join $here board_b.sdc]
    read_sdc [file join $here board_cdc.sdc]
    update_timing -mode basic
    report_timing_summary -ep_num 30 -file gate.timing
    export_db gate.db
    place
    route
    update_timing -mode final
    report_timing_summary -ep_num 100 -path_num 3 -file route.timing
    report_timing_status -file route.status
    report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks
    report_timing_exception -file route.exceptions
    check_design
    check_timing -verbose -file route.check
    report_area -io_info -file route.area
    export_sdc -file route.derived.sdc
    export_db route.db

    # ---- Optional bitstream. OFF by default: STA must be read first. ----
    # Programming hardware is an explicit user decision, not a side effect of
    # running the flow.
    if {[info exists ::env(SAFEVISION_BOARD_BITGEN)] && $::env(SAFEVISION_BOARD_BITGEN) eq "1"} {
        puts "BOARD TD WARNING: bitgen requested while the global setup path is NOT converged."
        puts "BOARD TD WARNING: the reported violation is the packaged SDRAM hard-IP physical"
        puts "BOARD TD WARNING: path (dq -> internal pad), which user RTL cannot retime; it is"
        puts "BOARD TD WARNING: judged by measurement per the vendor/user convention. This"
        puts "BOARD TD WARNING: bitstream is NOT a statement that timing has passed."
        bitgen -bit [file join $out safevision_top.bit]
        export_bitgen_param -file [file join $out .bitgen_param.f]
        puts "BOARD TD BITGEN DONE mode=$board_mode (timing NOT converged; see warnings above)"
    }
} err]} {puts stderr "BOARD TD FAILED: $err";exit 1}
puts "BOARD TD ROUTED mode=$board_mode (inspect timing/I-O health before any programming)"
exit 0
