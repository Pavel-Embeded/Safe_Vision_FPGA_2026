# TD6.2.168116 board bring-up: synthesize/place/route/STA with real pins.
# Target: safevision_top on HX4S20C, HDMI B output, package-in SDRAM.
# Route/report only. A successful Tcl exit means the reports were produced;
# run_board_sta.ps1 performs the separate fail-closed timing gate. This flow
# alone does not prove HDMI electrical behavior or SDRAM AC correctness.
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

set paths {}
set source_file [open [file join $here board_sources.list] r]
set source_lines [split [read $source_file] "\n"]
close $source_file
foreach line $source_lines {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} {continue}
    set line [string map [list @video_pll@ $video_pll] $line]
    if {[string match vendor/* $line]} {
        lappend paths [file join $vend [string range $line 7 end]]
    } else {lappend paths [file join $root safevision $line]}
}
foreach f $paths {if {![file isfile $f]} {error "Missing source: $f"}}

if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    # Official TD 6.2 implementation options. Improve actual routed slack
    # without relaxing clock periods or exempting business data paths.
    set_param place effort high
    set_param place post_place_opt high
    set_param route timing greedy
    set_param route fix_hold on
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
    if {[llength [get_nets {core/display/fetch/fifo_reset}]] == 0} {error "Missing preserved FIFO asynchronous assertion net"}
    update_timing -mode basic
    report_timing_summary -ep_num 30 -file gate.timing
    export_db gate.db
    report_param -detail -stage place -file place.params
    report_param -detail -stage route -file route.params
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

    # Route/report only. run_board_sta.ps1 validates these final reports before
    # a separate import_db/bitgen invocation. Environment flags cannot bypass
    # that gate inside this flow.
} err]} {puts stderr "BOARD TD FAILED: $err";exit 1}
puts "BOARD TD ROUTED mode=$board_mode (inspect timing/I-O health before any programming)"
exit 0
