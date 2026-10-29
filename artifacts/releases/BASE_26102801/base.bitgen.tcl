if {[catch {
 import_db {D:/Codex/sv_scroll261028/native228/base/route.db}
 bitgen -bit {D:/Codex/sv_scroll261028/final_base271/base.pending.bit}
 export_bitgen_param -file {D:/Codex/sv_scroll261028/final_base271/base.bitgen.params}
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 BITGEN COMPLETE"
exit 0
