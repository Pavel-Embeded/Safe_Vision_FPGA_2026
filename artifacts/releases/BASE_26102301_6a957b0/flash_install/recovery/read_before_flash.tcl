if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
puts "FLASH921_IDENTIFY_BEGIN"
get_flash_manufacturer -cable 0 -spd 7
puts "FLASH921_IDENTIFY_END"
foreach copy {a b} {
 set output D:/Codex/svflash921/original_flash_$copy.bin
 if {[file exists $output]} {error "Preserve original backup"}
 puts "FLASH921_FULL_BACKUP_BEGIN $copy"
 if {[catch {read_flash -start_addr 0x000000 -length 2097152 -output $output -level 1 -total 1 -cable 0} err]} {
  puts stderr "FLASH921_BACKUP_FAILED: $err"
  exit 1
 }
 if {![file isfile $output] || [file size $output]!=2097152} {error "Incomplete backup"}
 puts "FLASH921_FULL_BACKUP_DONE $copy"
}
puts "FLASH921_BACKUP_COMPLETED"
exit 0
