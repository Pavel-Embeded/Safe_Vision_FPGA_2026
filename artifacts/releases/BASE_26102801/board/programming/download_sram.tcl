set candidate {D:/Safe_Vision_FPGA_2026/artifacts/releases/BASE_26102801/SafeVision_BASE_75b34e6.bit}
puts "BW_TICKER_SRAM_BEGIN"
if {[catch {download -bit $candidate -mode jtag -spd 7 -cable 0} err]} {
 puts stderr "BW_TICKER_SRAM_FAILED: $err"
 exit 1
}
puts "BW_TICKER_SRAM_COMPLETED"
exit 0