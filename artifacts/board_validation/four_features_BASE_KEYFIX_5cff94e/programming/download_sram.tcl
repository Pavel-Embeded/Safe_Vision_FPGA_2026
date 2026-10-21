set candidate {D:/Safe_Vision_FPGA_2026/artifacts/v3/four_features_BASE_KEYFIX_5cff94e/SafeVision_BASE_5cff94e.bit}
if {![file isfile $candidate]} {error "Missing strictly approved candidate"}
puts "BW_HANDBOOK_SRAM_BEGIN"
if {[catch {download -bit $candidate -mode jtag -spd 7 -cable 0} err]} {
 puts stderr "BW_HANDBOOK_SRAM_FAILED: $err"
 exit 1
}
puts "BW_HANDBOOK_SRAM_COMPLETED"
exit 0