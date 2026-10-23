set candidate {D:/Safe_Vision_FPGA_2026/artifacts/flash_install/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit}
if {![file isfile $candidate] || [file size $candidate]!=636622} {error "Unexpected approved bitstream"}
if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
puts "FLASH921_PROGRAM_BEGIN"
if {[catch {download -bit $candidate -mode program_spi -spd 7 -cable 0} err]} {
 puts stderr "FLASH921_PROGRAM_FAILED: $err"
 exit 1
}
puts "FLASH921_PROGRAM_RETURNED"
puts "FLASH921_VERIFY_BEGIN"
if {[catch {download -bit $candidate -mode verify_spi -spd 7 -cable 0} err]} {
 puts stderr "FLASH921_VERIFY_FAILED: $err"
 exit 1
}
puts "FLASH921_VERIFY_RETURNED"
exit 0
