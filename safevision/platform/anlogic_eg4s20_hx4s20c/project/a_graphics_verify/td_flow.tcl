# TD 6.2.1 CLI: td_commands_prompt.exe base.tcl (also hd.tcl / basics.tcl).
# Synthesizes, routes, checks design and reports INTERNAL timing. No bitgen.
if {![info exists a_verify_mode] || $a_verify_mode ni {base hd basics}} {error "Invalid verify mode"}
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set repo_root [file normalize $::env(SAFEVISION_REPO)]}
set platform [file join $repo_root safevision platform anlogic_eg4s20_hx4s20c]
set out [file join $repo_root safevision build out a_graphics_verify $a_verify_mode]
if {[info exists ::env(SAFEVISION_A_VERIFY_OUT)]} {set out [file join [file normalize $::env(SAFEVISION_A_VERIFY_OUT)] $a_verify_mode]}
file mkdir $out
file copy -force [file join $repo_root safevision assets fonts font8x16.mem] [file join $out font8x16.mem]
cd $out
set files [list [file join $platform rtl clock reset_sync.v]]
if {$a_verify_mode eq "basics"} {
    foreach name {a_counter a_debounce a_edge_detect a_mode_fsm} {lappend files [file join $repo_root safevision rtl common $name.v]}
    set top a_basics_verify_top
    set define A_GRAPHICS_HD=0
} else {
    set hd [expr {$a_verify_mode eq "hd"}]
    set pll [expr {$hd ? "sv_video_hd_pll" : "sv_video_vga_pll"}]
    lappend files [file join $platform ip pll $pll.v]
    foreach path {video_timing/video_timing.v video_pipeline/video_pipeline.v pattern_generator/pattern_generator.v graphics_rom/font8x16_rom.v osd_overlay/osd_status_text.v osd_overlay/osd_coordinate_text.v osd_overlay/osd_overlay.v osd_overlay/a_graphics_frontend.v} {
        lappend files [file join $repo_root safevision rtl video $path]
    }
    set top a_graphics_verify_top
    set define A_GRAPHICS_HD=$hd
}
lappend files [file join $script_dir $top.v]
foreach f $files {if {![file isfile $f]} {error "Missing source: $f"}}
if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    read_hdl -file [join $files " "] -include_dir [file join $repo_root safevision rtl include] -define $define -top $top
    read_adc [file join $script_dir pin.adc]
    optimize_rtl
    report_area -file rtl.area
    read_sdc [file join $script_dir clock.sdc]
    optimize_gate
    legalize_phy_inst
    read_sdc [file join $script_dir clock.sdc]
    place
    route
    update_timing -mode final
    report_timing_summary -ep_num 100 -path_num 3 -file route.timing
    report_timing_status -file route.status
    report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks
    check_design
    check_timing -verbose -file route.check
    report_area -io_info -file route.area
    export_db route.db
} err]} {puts stderr "A PRE10 TD FAILED: $err";exit 1}
puts "A PRE10 TD ROUTED mode=$a_verify_mode"
exit 0
