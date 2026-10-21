if {[catch {
 import_db {D:/Codex/svformal476/base/td/base/route.db}
 bitgen -bit {D:/Codex/svkeybit484/base.pending.bit}
 export_bitgen_param -file {D:/Codex/svkeybit484/base.bitgen.params}
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 BITGEN COMPLETE"
exit 0
