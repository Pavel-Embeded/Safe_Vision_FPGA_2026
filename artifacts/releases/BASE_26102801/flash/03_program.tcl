if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
set candidate {D:/Codex/sv_scroll261028/wav_reject_barrier_source/artifacts/releases/BASE_26102801/SafeVision_BASE_75b34e6.bit}
if {[catch {download -bit $candidate -mode program_spi -spd 7 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
puts "SV_FLASH_PROGRAM_DONE"
exit 0
