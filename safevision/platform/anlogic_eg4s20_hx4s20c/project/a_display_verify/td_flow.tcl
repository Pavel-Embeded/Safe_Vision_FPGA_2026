
if {![info exists a_display_mode] || $a_display_mode ni {base hd}} {error "Select base or hd"}
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set root [file normalize $::env(SAFEVISION_REPO)]}
set out [file join $root safevision build out a_display_verify $a_display_mode]
if {[info exists ::env(SAFEVISION_A_DISPLAY_OUT)]} {set out [file join [file normalize $::env(SAFEVISION_A_DISPLAY_OUT)] $a_display_mode]}
file mkdir $out
file copy -force [file join $root safevision assets fonts font8x16.mem] [file join $out font8x16.mem]
cd $out
set paths {
 platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_ip.v
 platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_eram.v
 platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/a_pixel_fifo.v
 platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v
 rtl/video/frame_reader/pixel_word_packer.v rtl/video/frame_reader/frame_slot_commit.v
 rtl/video/frame_reader/frame_reader.v rtl/video/frame_reader/a_frame_fetch_bridge.v
 rtl/video/video_pipeline/a_video_display_core.v rtl/video/video_pipeline/video_pipeline.v
 rtl/video/video_cdc/video_cdc_mailbox.v rtl/video/video_cdc/video_level_sync.v
 rtl/video/video_compositor/video_layer_delay.v rtl/video/video_compositor/video_compositor.v
 rtl/video/osd_overlay/osd_text_layer.v rtl/video/osd_overlay/osd_status_text.v
 rtl/video/graphics_rom/font8x16_rom.v rtl/video/video_timing/video_timing.v
 rtl/memory/video_read_dma.v rtl/memory/frame_swap_cdc.v
}
set files {};foreach p $paths {lappend files [file join $root safevision $p]}
lappend files [file join $here a_display_verify_top.v]
if {[catch {
 import_device eagle_s20.db -package EG4S20BG256
 read_hdl -file [join $files " "] -include_dir [file join $root safevision rtl include] -define "A_DISPLAY_HD=[expr {$a_display_mode eq "hd"}]" -top a_display_verify_top
 optimize_rtl
 read_sdc [file join $here ${a_display_mode}.sdc]
 read_sdc [file join $here cdc.sdc]
 optimize_gate
 legalize_phy_inst
 read_sdc [file join $here ${a_display_mode}.sdc]
 read_sdc [file join $here cdc.sdc]
 update_timing -mode basic
 report_timing_summary -ep_num 30 -file gate.timing
 export_db gate.db
 place
 route
 update_timing -mode final
 report_timing_summary -ep_num 100 -path_num 3 -file route.timing
 report_timing_status -file route.status
 report_timing_exception -file route.exceptions
 check_timing -verbose -file route.check
 check_design
 report_area -io_info -file route.area
 export_sdc -file route.derived.sdc
 export_db route.db
} err]} {puts stderr "A DISPLAY TD FAILED: $err";exit 1}
puts "A DISPLAY TD ROUTED mode=$a_display_mode (inspect timing/CDC/I/O health)"
exit 0
