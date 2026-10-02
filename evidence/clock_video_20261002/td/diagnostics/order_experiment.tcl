import_device eagle_s20.db -package EG4S20BG256
import_db D:/Codex/2026-09-30/sao/work/final_td/base/route.db
clear_sdc -user
read_sdc D:/Codex/2026-09-30/sao/work/td_clock_verify/verify_clock.sdc
update_timing -mode final
report_timing_summary -file D:/Codex/2026-09-30/sao/work/final_td/base/order_before.timing
check_timing -verbose -file D:/Codex/2026-09-30/sao/work/final_td/base/order_before.check
report_clock_summary -levels 20 -expand_buckets -debug -file D:/Codex/2026-09-30/sao/work/final_td/base/order.clock_tree
check_timing -verbose -file D:/Codex/2026-09-30/sao/work/final_td/base/order_after.check
report_timing_summary -file D:/Codex/2026-09-30/sao/work/final_td/base/order_after.timing
exit 0
