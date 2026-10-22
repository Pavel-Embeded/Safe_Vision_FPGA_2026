if {[catch {
 import_db {D:/Codex/svmultires510/native/base/route.db}
 bitgen -bit {D:/Codex/svmedia_bit525/base.pending.bit}
 export_bitgen_param -file {D:/Codex/svmedia_bit525/base.bitgen.params}
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 BITGEN COMPLETE"
exit 0
