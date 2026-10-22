if {[catch {download -bit {D:/Codex/svmedia_portable521/BASE_MEDIA_ALIAS_261022_34462ee/SafeVision_BASE_34462ee.bit} -mode jtag -spd 7 -cable 0} err]} {puts stderr "MEDIA SRAM FAILED $err";exit 1}
puts "MEDIA SRAM COMPLETED"
exit 0
