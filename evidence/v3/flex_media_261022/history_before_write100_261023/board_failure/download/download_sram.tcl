set candidate {D:/Safe_Vision_FPGA_2026/artifacts/board_acceptance/BASE_FLEX_261023_9c5502e/SafeVision_BASE_9c5502e.bit}
if {![file isfile $candidate]} {error "Missing strictly approved bitstream"}
puts "BW_HANDBOOK_SRAM_BEGIN"
if {[catch {download -bit $candidate -mode jtag -spd 7 -cable 0} err]} {
 puts stderr "BW_HANDBOOK_SRAM_FAILED: $err"
 exit 1
}
puts "BW_HANDBOOK_SRAM_COMPLETED"
exit 0