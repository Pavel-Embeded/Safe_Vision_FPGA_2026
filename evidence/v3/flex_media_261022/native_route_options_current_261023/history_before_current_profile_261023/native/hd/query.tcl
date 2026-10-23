if {[catch {
 import_db {D:/Codex/svarea427/pr14/hd/place.db}
 source {D:/Codex/svflex537/candidate803/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_build_parameters.tcl}
 source {D:/Codex/svflex537/candidate803/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_build_parameters_hd.tcl}
 report_param -detail -stage route -file route.params
 set fd [open route.hidden.params w]
 puts $fd "route post_route_opt [get_param route post_route_opt]"
 close $fd
} err]} {puts stderr "ROUTE OPTION QUERY FAILED: $err";exit 1}
puts "ROUTE_PARAM_NATIVE_ACK_COMPLETE"
exit 0
