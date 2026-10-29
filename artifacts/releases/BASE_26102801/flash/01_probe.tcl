if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
puts "SV_FLASH_PROBE_BEGIN"
get_flash_manufacturer -cable 0 -spd 7
puts "SV_FLASH_PROBE_DONE"
exit 0
