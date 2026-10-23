if {[catch {
 import_db {D:/Codex/svflex537/native892/base/route.db}
 bitgen -bit {D:/Codex/svflex537/approval915/base.pending.bit}
 export_bitgen_param -file {D:/Codex/svflex537/approval915/base.bitgen.params}
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 BITGEN COMPLETE"
exit 0
