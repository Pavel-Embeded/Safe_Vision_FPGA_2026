


if {![info exists sv_verify_mode] ||
    ($sv_verify_mode ne "base" && $sv_verify_mode ne "hd")} {
    puts stderr "Set sv_verify_mode to base or hd before sourcing postroute.tcl"
    exit 1
}
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. .. .. .. ..]]
if {![file exists [file join $repo_root safevision rtl video video_timing video_timing.v]]} {
    if {![info exists ::env(SAFEVISION_REPO)]} {
        puts stderr "Cannot find repository; set SAFEVISION_REPO"
        exit 1
    }
    set repo_root [file normalize $::env(SAFEVISION_REPO)]
}
set out_dir [file join $repo_root safevision build out clock_video_verify $sv_verify_mode]
if {[info exists ::env(SAFEVISION_VERIFY_OUT)]} {
    set out_dir [file join [file normalize $::env(SAFEVISION_VERIFY_OUT)] $sv_verify_mode]
}
set sv_post_route_db [file join $out_dir route.db]
set sv_post_sdc [file join $script_dir verify_clock.sdc]
foreach f [list $sv_post_route_db $sv_post_sdc] {
    if {![file isfile $f]} {
        puts stderr "Missing postroute input: $f"
        exit 1
    }
}
file mkdir [file join $out_dir postroute]
cd [file join $out_dir postroute]
if {[catch {
    puts "POSTROUTE input DB before import_device: $sv_post_route_db"
    import_device eagle_s20.db -package EG4S20BG256
    puts "POSTROUTE input DB after import_device: $sv_post_route_db"
    eval [list import_db $sv_post_route_db]
    clear_sdc -user
    eval [list read_sdc $sv_post_sdc]
    update_timing -mode final
    report_timing_summary -ep_num 100 -path_num 3 -file final.timing
    report_timing_status -file final.status
    report_clock_summary -levels 20 -expand_buckets -debug -file final.clock_summary
    report_clock_intersection -file final.clock_intersection
    report_timing_exception -file final.exceptions
    report_timing_ignored -file final.ignored
    check_timing -verbose -file final.check_timing
    report_area -io_info -file final.area
    export_sdc -file final.derived.sdc
    all_clocks -verbose
    report_nets [get_nets -hier {*clk0_out*}] -connection
    report_nets [get_nets -hier {*clk0_buf*}] -connection
    report_nets [get_nets -hier {*board_clk*}] -connection
} err]} {
    puts stderr "TD POSTROUTE FAILED ($sv_verify_mode): $err"
    exit 1
}
puts "TD POSTROUTE COMPLETE ($sv_verify_mode)."
puts "Check all 8 clocks, 0 no-clock entries, setup/hold/recovery/removal and remaining warnings."
puts "No timing exception was added; external 5 input/17 output timing remains unverified."
exit 0
