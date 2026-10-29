set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set root [file normalize $::env(SAFEVISION_REPO)]}
if {![info exists ::env(SAFEVISION_PLL_OUT)]} {error "Set SAFEVISION_PLL_OUT to an isolated ASCII directory"}
file mkdir $::env(SAFEVISION_PLL_OUT)
cd [file normalize $::env(SAFEVISION_PLL_OUT)]
if {[catch {
 import_device eagle_s20.db -package EG4S20BG256
 read_hdl -file "[file join $root safevision platform anlogic_eg4s20_hx4s20c ip pll sv_v3_memory_pll.v] [file join $root safevision verification unit v3_pll_probe.v]" -top v3_pll_probe
 optimize_rtl
 optimize_gate
 legalize_phy_inst
 read_sdc [file join $here pll50_check.sdc]
 place
 route
 update_timing -mode final
 report_clock_summary -levels 20 -expand_buckets -debug -file pll50.clocks
 report_timing_summary -ep_num 20 -file pll50.timing
 export_sdc -file pll50.derived.sdc
 report_area -file pll50.area
 export_db pll50.gate.db
} err]} {puts stderr "V3 PLL FAILED: $err";exit 1}
puts "V3 PLL DERIVATION COMPLETE"
exit 0
