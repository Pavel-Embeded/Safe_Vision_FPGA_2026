if {[catch {
 import_db {D:/Codex/svflex537/native618/base/gate.db}
 source {D:/Codex/svflex537/candidate618/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_build_parameters.tcl}
 source {D:/Codex/svflex537/candidate618/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_build_parameters_base.tcl}
 report_param -detail -stage place -file place.params
 set fd [open place.seed.params w]
 puts $fd "place seed [get_param place seed]"
 close $fd
} err]} {puts stderr "PLACE OPTION QUERY FAILED $err";exit 1}
puts "PLACEMENT621 ACTUAL ACK COMPLETE"
exit 0
