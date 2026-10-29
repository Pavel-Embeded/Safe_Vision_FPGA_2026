# Import the exact serialized synthesis checkpoint in a fresh TD process.
# Source, constraints, hold repair and final reports use the production flow.
set board_mode $::env(SAFEVISION_BOARD_MODE)
if {$board_mode ni {base hd}} {error "Select base or hd"}
set here [file dirname [file normalize [info script]]]
set root [file normalize $::env(SAFEVISION_REPO)]
set out [file join [file normalize $::env(SAFEVISION_V3_OUT)] $board_mode]
cd $out
if {[catch {
 import_db [file join $out gate.db]
 source [file join $here v3_build_parameters.tcl]
 set mode_parameters [file join $here v3_build_parameters_${board_mode}.tcl]
 if {[file isfile $mode_parameters]} {source $mode_parameters}
 # Remove the pre-map clock objects before rebuilding mapped collections.
 clear_sdc
 read_sdc [file join $here v3_board.sdc]
 read_sdc [file join $here v3_cdc.sdc]
 update_timing -mode basic
 source [file join $here v3_cdc_audit.tcl]
 report_timing_summary -ep_num 30 -file gate.timing
 report_param -detail -stage place -file place.params
 report_param -all -stage place -file place.all.params
 # TD omits default seed0 even with -all. Query the actual registered value;
 # absence from a table is never interpreted as successful acknowledgement.
 set seed_file [open place.seed.params w]
 puts $seed_file "place seed [get_param place seed]"
 close $seed_file
 report_param -detail -stage route -file route.params
 place
 # Placement estimates are diagnostics; final acceptance uses fresh routed STA.
 report_timing_summary -ep_num 40 -file place.timing
 report_timing_exception -file place.exceptions
 report_area -io_info -file place.area
 export_db place.db
 # Read the actual route-only option after placement, before routing.
 set route_hidden [open route.hidden.params w]
 puts $route_hidden "route post_route_opt [get_param route post_route_opt]"
 close $route_hidden
 route
 # TD skips its automatic hold repair above 90% slice utilization. Invoke the
 # documented repair explicitly; final fresh all-corner STA remains mandatory.
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
 # This TD release mutates clock objects while expanding clock diagnostics.
 # Preserve the routed database and all formal reports before that diagnostic.
 report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 TD ROUTED mode=$board_mode (bitgen still requires strict report gate)"
exit 0
