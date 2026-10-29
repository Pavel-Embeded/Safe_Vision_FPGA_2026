if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
set output {D:/Codex/sv_scroll261028/flash_install292/before_flash_a.bin}
if {[file exists $output]} {error "Preserve existing Flash capture"}
if {[catch {read_flash -start_addr 0x000000 -length 2097152 -output $output -level 1 -total 1 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
if {![file isfile $output] || [file size $output]!=2097152} {error "Incomplete Flash capture"}
puts "SV_FLASH_READ_A_DONE"
set output {D:/Codex/sv_scroll261028/flash_install292/before_flash_b.bin}
if {[file exists $output]} {error "Preserve existing Flash capture"}
if {[catch {read_flash -start_addr 0x000000 -length 2097152 -output $output -level 1 -total 1 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
if {![file isfile $output] || [file size $output]!=2097152} {error "Incomplete Flash capture"}
puts "SV_FLASH_READ_B_DONE"

exit 0
