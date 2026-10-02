# ASCII only for Windows PowerShell 5.1 compatibility.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$required = @(
    'README.md', 'docs/PROJECT_STRUCTURE.md', 'docs/interface_spec.md',
    'docs/architecture/module_registry.md', 'docs/requirements/traceability.md',
    'docs/verification/test_matrix.md', 'safevision/rtl/top/README.md',
    'safevision/rtl/video/README.md', 'safevision/rtl/control/README.md',
    'safevision/platform/anlogic_eg4s20_hx4s20c/constraints/README.md',
    'safevision/platform/anlogic_eg4s20_hx4s20c/constraints/pin.adc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/constraints/timing.sdc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v',
    'safevision/rtl/storage/spi_master.v',
    'safevision/verification/unit/tb_sd_sector_reader.sv',
    'safevision/verification/unit/tb_clock_reset_ctrl.sv',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v',
    'safevision/tools/run_clock_sim.ps1',
    'evidence/README.md'
)
$aModuleDirs = @(
    'safevision/rtl/video/video_timing',
    'safevision/rtl/video/pattern_generator',
    'safevision/rtl/video/graphics_rom',
    'safevision/rtl/video/osd_overlay',
    'safevision/rtl/video/video_pipeline',
    'safevision/rtl/video/frame_reader',
    'safevision/rtl/video/video_compositor',
    'safevision/rtl/video/safe_scene_gen',
    'safevision/rtl/video/emergency_mux',
    'safevision/rtl/video/video_cdc',
    'safevision/rtl/top/safevision_core',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/hdmi',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/chipwatcher',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pixel_fifo',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/graphics_bram',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/hdmi'
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) { $missing += $rel }
}
foreach ($rel in $aModuleDirs) {
    $readme = Join-Path (Join-Path $root $rel) 'README.md'
    if (-not (Test-Path -LiteralPath $readme)) { $missing += "$rel/README.md" }
}
$runner = Join-Path $root 'safevision/tools/run_sim.ps1'
if (Test-Path -LiteralPath $runner) {
    $sv = Join-Path $root 'safevision'
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($runner), '"(\.\./(?:rtl|platform)/[^\"]+|models/[^\"]+|unit/[^\"]+)"')) {
        $rel = $m.Groups[1].Value
        $base = Join-Path $sv 'verification'
        if (-not (Test-Path -LiteralPath (Join-Path $base $rel))) { $missing += "run_sim: $rel" }
    }
} else { $missing += 'safevision/tools/run_sim.ps1' }
if ($missing.Count -gt 0) {
    $missing | ForEach-Object { Write-Error "MISSING $_" }
    exit 1
}
$svARequired = @(
    'docs/clock_video_change_log.md',
    'docs/clock_video_implementation.md',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_audio_pll.ipc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_audio_pll.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_system_pll.ipc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_system_pll.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_hd_pll.ipc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_hd_pll.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_vga_pll.ipc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_vga_pll.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/README.md',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/base.tcl',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/base_postroute.tcl',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/clock_video_verify_top.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/hd.tcl',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/hd_postroute.tcl',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/postroute.tcl',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/td_flow.tcl',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/verify_clock.sdc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/verify_pin.adc',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_gen.v',
    'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_video_subsystem.v',
    'safevision/rtl/include/video_mode_defs.vh',
    'safevision/rtl/video/video_timing/video_timing.v',
    'safevision/tools/check_pll_profiles.py',
    'safevision/tools/run_video_clock_sim.ps1',
    'safevision/tools/run_video_clock_td.ps1',
    'safevision/verification/unit/tb_clock_video_subsystem.sv',
    'safevision/verification/unit/tb_frame_swap_real_frame.sv',
    'safevision/verification/unit/tb_video_timing.sv'
)
foreach ($svARel in $svARequired) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $svARel))) { throw "MISSING A $svARel" }
}
Write-Output 'LAYOUT PASS: required paths and run_sim file references exist.'
