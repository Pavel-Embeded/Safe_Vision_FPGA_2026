if {[catch {
 import_db {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/release113_9d40698/td/base/route.db}
 bitgen -bit {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/release113_9d40698/td/base/safevision_v3_top.pending.bit}
 export_bitgen_param -file {D:/Codex/2026-10-15/github-plugin-github-openai-curated-remote/work/runs/release113_9d40698/td/base/bitgen.params}
} err]} {puts stderr "V3 TD FAILED: $err";exit 1}
puts "V3 BITGEN COMPLETE"
exit 0
