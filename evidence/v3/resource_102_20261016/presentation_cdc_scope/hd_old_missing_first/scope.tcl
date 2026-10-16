if {[catch {
 cd {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/presentation_cdc_scope/hd_old_missing_first}
 import_db {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/control_set_packing_r2/control4_hd/td/hd/placed.db}
 clear_sdc
 read_sdc {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/presentation_cdc_scope/hd_old_missing_first/v3_board.sdc}
 read_sdc {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/presentation_cdc_scope/hd_old_missing_first/v3_cdc.sdc}
 update_timing -mode basic
 set first [get_regs {video/present_s1}]
 set second [get_regs {video/present_s2}]
 puts "CDC_FIRST_COUNT=[llength $first] CDC_SECOND_COUNT=[llength $second]"
 if {[llength $first]!=1 || [llength $second]!=1} {error "missing exact sampling stage"}
 report_timing_path -from [get_regs {video/presentation/presentation_fault}] -to $first -file async_first.timing
 report_timing_path -from $first -to $second -file local_second.timing
} err]} {puts stderr "CDC SCOPE FAILED: $err";exit 1}
puts "NORMAL_CDC_SCOPE_PROBE_COMPLETE"
exit 0
