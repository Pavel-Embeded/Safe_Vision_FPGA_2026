
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. .. .. .. ..]]
if {[info exists ::env(SAFEVISION_REPO)]} {set repo_root [file normalize $::env(SAFEVISION_REPO)]}
set out [file join $repo_root safevision build out a_graphics_verify font]
if {[info exists ::env(SAFEVISION_A_VERIFY_OUT)]} {set out [file join [file normalize $::env(SAFEVISION_A_VERIFY_OUT)] font]}
file mkdir $out
cd $out
if {[catch {
    import_device eagle_s20.db -package EG4S20BG256
    read_hdl -file [file join $repo_root safevision rtl video graphics_rom font8x16_rom.v] -top font8x16_rom
    optimize_rtl
    optimize_gate
    legalize_phy_inst
    write_verilog font_gate.v
    report_area -file font_gate.area
} err]} {puts stderr "A FONT MAP FAILED $err";exit 1}
puts "A FONT MAP EXPORTED"
exit 0
