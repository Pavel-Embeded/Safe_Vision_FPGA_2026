
if {![info exists board_mode] || $board_mode ni {base hd}} {error "Select base or hd"}
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set root [file normalize $::env(SAFEVISION_REPO)]}
set out [file join $root safevision build out v3_board_verify $board_mode]
if {[info exists ::env(SAFEVISION_V3_OUT)]} {set out [file join [file normalize $::env(SAFEVISION_V3_OUT)] $board_mode]}
file mkdir $out
set asset_file [open [file join $here v3_board_assets.list] r]
set asset_lines [split [read $asset_file] "\n"]
close $asset_file
foreach asset $asset_lines {
 set asset [string trim $asset]
 if {$asset eq "" || [string index $asset 0] eq "#"} {continue}
 set input_asset [file join $root safevision $asset]
 if {![file isfile $input_asset]} {error "Missing production ROM asset: $input_asset"}
 file copy -force $input_asset [file join $out [file tail $asset]]
}
cd $out
set hd [expr {$board_mode eq "hd"}]
set video_pll [expr {$hd ? "sv_video_hd_pll.v" : "sv_video_vga_pll.v"}]
set mode_define [expr {$hd ? "hd_mode.v" : "base_mode.v"}]
set paths {}
set source_manifest [file join $here v3_board_sources.list]
if {$board_mode eq "hd" && [file isfile [file join $here v3_board_sources_hd.list]]} {
 set source_manifest [file join $here v3_board_sources_hd.list]
}
set source_file [open $source_manifest r]
set source_lines [split [read $source_file] "\n"]
close $source_file
foreach line $source_lines {
 set line [string trim $line]
 if {$line eq "" || [string index $line 0] eq "#"} {continue}
 set line [string map [list @video_pll@ $video_pll @mode_define@ $mode_define] $line]
 lappend paths [file join $root safevision $line]
}
foreach f $paths {if {![file isfile $f]} {error "Missing production source: $f"}}
if {[catch {
 import_device eagle_s20.db -package EG4S20BG256
 source [file join $here v3_build_parameters.tcl]
 set mode_parameters [file join $here v3_build_parameters_${board_mode}.tcl]
 if {[file isfile $mode_parameters]} {source $mode_parameters}
 report_param -detail -stage rtl -file rtl.params
 report_param -detail -stage gate -file gate.params
 set gate_hidden [open gate.hidden.params w]
 foreach key {bdd_opt lut4_map} {puts $gate_hidden "gate $key [get_param gate $key]"}
 close $gate_hidden
 read_hdl -file [join $paths " "] -include_dir [file join $root safevision rtl include] -top safevision_v3_top
 read_adc [file join $here v3_board.adc]
 set physical_adc [file join $here v3_physical_${board_mode}.adc]
 if {![file isfile $physical_adc]} {set physical_adc [file join $here v3_physical.adc]}
 if {[file isfile $physical_adc]} {read_adc $physical_adc}
 optimize_rtl
 report_area -file rtl.area
 read_sdc [file join $here v3_board.sdc]
 optimize_gate
 legalize_phy_inst
 report_area -io_info -file gate.area
 report_area -verbose -file gate.hierarchy.area
 write_verilog gate.netlist.v
 export_db gate.db
 if {[info exists ::env(SAFEVISION_V3_SYNTH_ONLY)] && $::env(SAFEVISION_V3_SYNTH_ONLY) eq "1"} {
  puts "V3 TD SYNTHESIZED mode=$board_mode (not final routed signoff)"
  exit 0
 }

 clear_sdc
 read_sdc [file join $here v3_board.sdc]
 read_sdc [file join $here v3_cdc.sdc]
 update_timing -mode basic
 source [file join $here v3_cdc_audit.tcl]
 report_timing_summary -ep_num 30 -file gate.timing
 report_param -detail -stage place -file place.params
 report_param -all -stage place -file place.all.params


 set seed_file [open place.seed.params w]
 puts $seed_file "place seed [get_param place seed]"
 close $seed_file
 report_param -detail -stage route -file route.params
 place

 report_timing_summary -ep_num 40 -file place.timing
 report_timing_exception -file place.exceptions
 report_area -io_info -file place.area
 export_db place.db

 set route_hidden [open route.hidden.params w]
 puts $route_hidden "route post_route_opt [get_param route post_route_opt]"
 close $route_hidden
 route


 fix_hold
 update_timing -mode final
 report_timing_summary -ep_num 200 -path_num 3 -file route.timing
 report_timing_status -file route.status
 report_timing_exception -ep_num 200 -path_num 8 -file route.exceptions
 check_design
 check_timing -verbose -file route.check
 report_area -io_info -file route.area
 export_sdc -file route.derived.sdc
 write_verilog route.netlist.v
 export_db route.db


 report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 TD ROUTED mode=$board_mode (bitgen still requires strict report gate)"
exit 0
