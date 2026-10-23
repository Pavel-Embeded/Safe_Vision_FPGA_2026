cd {D:/Codex/svflex537/native892/base}
if {[catch {
 import_db {D:/Codex/svflex537/native892/base/route.db}
 clear_sdc
 read_sdc {D:/Codex/svflex537/candidate892/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_board.sdc}
 read_sdc {D:/Codex/svflex537/candidate892/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_cdc.sdc}
 update_timing -mode final
 source {D:/Codex/svflex537/candidate892/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/v3_cdc_audit.tcl}
 report_timing_summary -ep_num 200 -path_num 3 -file route.timing
 report_timing_status -file route.status
 report_timing_exception -ep_num 200 -path_num 8 -file route.exceptions
 check_timing -verbose -file route.check
 export_sdc -file route.derived.sdc
 report_clock_summary -levels 20 -expand_buckets -debug -file route.clocks
 check_timing -verbose -file after_clock_report.check
 report_timing_summary -ep_num 200 -path_num 3 -file after_clock_report.timing
 report_timing_exception -ep_num 200 -path_num 8 -file after_clock_report.exceptions
} err]} {puts stderr "V3 FINAL STA FAILED: $err";exit 1}
puts "V3 FINAL STA COMPLETE"
exit 0
