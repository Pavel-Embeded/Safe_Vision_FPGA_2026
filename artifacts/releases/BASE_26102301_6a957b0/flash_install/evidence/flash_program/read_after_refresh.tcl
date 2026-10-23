if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
foreach copy {a b} {
 set output D:/Codex/svflash921/programmed_flash_$copy.bin
 if {[file exists $output]} {error "Preserve earlier post-program capture"}
 puts "FLASH921_POST_READ_BEGIN $copy"
 if {[catch {read_flash -start_addr 0x000000 -length 2097152 -output $output -level 1 -total 1 -cable 0} err]} {
  puts stderr "FLASH921_POST_READ_FAILED: $err"
  exit 1
 }
 if {![file isfile $output] || [file size $output]!=2097152} {error "Incomplete post-program read"}
 puts "FLASH921_POST_READ_DONE $copy"
}
puts "FLASH921_REFRESH_BEGIN"
set candidate {D:/Safe_Vision_FPGA_2026/artifacts/flash_install/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit}
if {[catch {download -bit $candidate -mode refresh -spd 7 -cable 0} err]} {
 puts stderr "FLASH921_REFRESH_FAILED: $err"
 exit 1
}
puts "FLASH921_REFRESH_DONE"
exit 0
