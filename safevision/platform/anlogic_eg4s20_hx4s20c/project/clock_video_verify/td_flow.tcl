# TD 6.2.1 non-project synthesis/place/route/internal-STA flow.
# Official command order: SWUG105 3.2.2 and 4.5; SWUG200 3.4.
# Run through td_commands_prompt.exe with base.tcl or hd.tcl.
# No bitgen: reset/request/probe I/O is unpinned and has no board timing budget.

if {![info exists sv_verify_mode] ||
    ($sv_verify_mode ne "base" && $sv_verify_mode ne "hd")} {
    puts stderr "Set sv_verify_mode to base or hd before sourcing td_flow.tcl"
    exit 1
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. .. .. .. ..]]
if {![file exists [file join $repo_root safevision rtl video video_timing video_timing.v]]} {
    if {![info exists ::env(SAFEVISION_REPO)]} {
        puts stderr "Cannot find repository; set SAFEVISION_REPO to its root"
        exit 1
    }
    set repo_root [file normalize $::env(SAFEVISION_REPO)]
}
set platform_dir [file join $repo_root safevision platform anlogic_eg4s20_hx4s20c]
set ip_dir       [file join $platform_dir ip pll]
set include_dir  [file join $repo_root safevision rtl include]
set out_dir      [file join $repo_root safevision build out clock_video_verify $sv_verify_mode]
if {[info exists ::env(SAFEVISION_VERIFY_OUT)]} {
    set out_dir [file join [file normalize $::env(SAFEVISION_VERIFY_OUT)] $sv_verify_mode]
}
file mkdir $out_dir
cd $out_dir

set mode_define 0
set video_ip sv_video_vga_pll.v
if {$sv_verify_mode eq "hd"} {
    set mode_define 1
    set video_ip sv_video_hd_pll.v
}

# Explicit source list. Only ONE video PLL file is included in each build.
# The .vh mode table is found through TD6.2.1's -include_dir, not compiled alone.
set hdl_sources [list \
    [file join $ip_dir sv_system_pll.v] \
    [file join $ip_dir $video_ip] \
    [file join $ip_dir sv_audio_pll.v] \
    [file join $platform_dir rtl clock clock_gen.v] \
    [file join $platform_dir rtl clock reset_sync.v] \
    [file join $platform_dir rtl clock clock_reset_ctrl.v] \
    [file join $platform_dir rtl clock clock_video_subsystem.v] \
    [file join $repo_root safevision rtl video video_timing video_timing.v] \
    [file join $script_dir clock_video_verify_top.v]]
set required_files [concat $hdl_sources [list \
    [file join $include_dir video_mode_defs.vh] \
    [file join $script_dir verify_clock.sdc] \
    [file join $script_dir verify_pin.adc]]]
foreach f $required_files {
    if {![file isfile $f]} {
        puts stderr "Missing required source/config: $f"
        exit 1
    }
}

set mf [open [file join $out_dir source_manifest.txt] w]
puts $mf "TD non-project internal STA; mode=$sv_verify_mode define=SV_VERIFY_HD=$mode_define"
puts $mf "Top=clock_video_verify_top; device=EG4S20BG256; db=eagle_s20.db"
puts $mf "Include directory: $include_dir"
foreach f $required_files {puts $mf $f}
close $mf

puts "=== SafeVision clock/video internal STA: $sv_verify_mode ==="
puts "Work output: $out_dir"

if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    read_hdl -file [join $hdl_sources " "] -include_dir $include_dir \
        -define "SV_VERIFY_HD=$mode_define" -top clock_video_verify_top
    read_adc [file join $script_dir verify_pin.adc]
    optimize_rtl
    report_area -file rtl.area

    # Official flow requires first SDC read before gate mapping.
    read_sdc [file join $script_dir verify_clock.sdc]
    optimize_gate
    legalize_phy_inst
    # Official flow requires re-reading SDC after PHY legalization.
    read_sdc [file join $script_dir verify_clock.sdc]
    update_timing -mode basic
    report_timing_summary -file gate.timing
    report_timing_status -file gate.status
    report_area -file gate.area
    export_db gate.db

    place
    update_timing -mode manhattan
    report_timing_summary -file place.timing
    report_area -io_info -file place.area
    report_clock_utilization -file place.clock_utilization
    if {![file exists place.clock_utilization]} {
        set cf [open place.clock_utilization.note w]
        puts $cf "TD did not emit report_clock_utilization for this device."
        puts $cf "For EG4S20BG256/TD6.2.168116 the console reports: Device not support command report_clock_utilization."
        puts $cf "Use route.area Clock Resource Statistics and route.clock_summary instead."
        close $cf
    }

    route
    update_timing -mode final
    report_timing_summary -ep_num 100 -path_num 3 -file route.timing
    report_timing_status -file route.status
    report_clock_summary -levels 20 -expand_buckets -debug -file route.clock_summary
    report_clock_intersection -file route.clock_intersection
    report_timing_exception -file route.exceptions
    report_timing_ignored -file route.ignored
    check_timing -verbose -file route.check_timing
    report_area -io_info -file route.area
    export_sdc -file route.derived.sdc
    # Preserve actual GCLK -> PLL.fbclk and PAD -> PLL.refclk connectivity
    # and Route Type in the TD console/log, in addition to health warnings.
    report_nets [get_nets -hier {*clk0_out*}] -connection
    report_nets [get_nets -hier {*clk0_buf*}] -connection
    report_nets [get_nets -hier {*board_clk*}] -connection
    report_qor -step route -file route.qor
    export_db route.db
} flow_error]} {
    puts stderr "TD FLOW FAILED ($sv_verify_mode): $flow_error"
    exit 1
}

puts "TD FLOW COMPLETE ($sv_verify_mode): inspect route.timing, route.check_timing,"
puts "route.clock_intersection, route.clock_summary and all warnings."
puts "Only internal mapped/routed timing is assessed; external I/O is unverified."
puts "Next run ${sv_verify_mode}_postroute.tcl in a fresh TD process to rebuild final clock metadata."
exit 0
