# ============================================================================
# run_ab_display_sim.ps1 - A/B display-level integration regression (ModelSim)
# ----------------------------------------------------------------------------
# Runs tb_ab_frame_display: a real BMP byte stream -> bmp_parser -> bmp_unpack
# -> frame_writer -> memory_arbiter write -> storage -> memory_arbiter read ->
# A's a_video_display_core -> screen pixels, comparing every displayed pixel
# against the source BMP.
#
# WHY A SEPARATE SCRIPT (not part of run_sim.ps1):
#   1. It needs A's display sources (rtl/video/**, the pixel FIFO IP, reset_sync)
#      in addition to B's, so folding it into run_sim.ps1 would couple B's main
#      gate to A's file list.
#   2. The design loads a font memory file, so the run directory must contain
#      font8x16.mem - a copy step that does not belong in B's plain gate.
#   run_all.ps1 runs this script too, so "one command" still covers everything.
#
# Prerequisite: ModelSim. Set MSIM_BIN or pass -ModelSimBin.
# ASCII only: PowerShell 5.1 may read BOM-less scripts as ANSI.
# ============================================================================
param(
    [string]$RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$ModelSimBin = $env:MSIM_BIN,
    [string]$RunDir      = (Join-Path (Split-Path $PSScriptRoot -Parent) 'verification/work_ab_display')
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ModelSimBin)) {
    [Console]::Error.WriteLine('Set MSIM_BIN or pass -ModelSimBin with the ModelSim win64 directory.')
    exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $ModelSimBin 'vsim.exe'))) {
    [Console]::Error.WriteLine("vsim.exe not found under $ModelSimBin")
    exit 2
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir   = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$vlib  = Join-Path $ModelSimBin 'vlib.exe'
$vlog  = Join-Path $ModelSimBin 'vlog.exe'
$vsim  = Join-Path $ModelSimBin 'vsim.exe'
$inc   = Join-Path $RepoRoot 'safevision/rtl/include'

# B side + A side + the SD card model + the vendor stub (sdram / sv_system_pll)
$files = @(
    'verification/models/vendor_ip_stub.sv',
    'verification/models/sd_spi_card_model.sv',
    'rtl/common/*.v',
    'rtl/media/*.v',
    'rtl/memory/*.v',
    'rtl/storage/*.v',
    'rtl/video/*/*.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v',
    'platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/*.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/*.v'
) | ForEach-Object { Get-ChildItem -Path (Join-Path $RepoRoot "safevision/$_") -ErrorAction SilentlyContinue } |
    Select-Object -ExpandProperty FullName

if ($files.Count -eq 0) { throw 'No RTL files matched - check RepoRoot' }

# The design loads a font memory file, so it must sit in the run directory.
Copy-Item -LiteralPath (Join-Path $RepoRoot 'safevision/assets/fonts/font8x16.mem') `
          -Destination (Join-Path $RunDir 'font8x16.mem') -Force

Push-Location -LiteralPath $RunDir
try {
    & $vlib work | Out-Null
    Write-Output '=== vlog (A+B RTL) ==='
    & $vlog "+incdir+$inc" $files
    if ($LASTEXITCODE -ne 0) { Write-Output 'COMPILE FAILED (RTL)'; exit 1 }

    Write-Output '=== vlog (tb_ab_frame_display) ==='
    & $vlog -sv "+incdir+$inc" (Join-Path $RepoRoot 'safevision/verification/unit/tb_ab_frame_display.sv')
    if ($LASTEXITCODE -ne 0) { Write-Output 'COMPILE FAILED (TB)'; exit 1 }

    Write-Output '=== vsim tb_ab_frame_display ==='
    $out = & $vsim -c -do 'run -all; quit -f' work.tb_ab_frame_display 2>&1 | Out-String
    Write-Output $out

    $pass = ([regex]::Matches($out, '\[PASS\]')).Count
    $fail = ([regex]::Matches($out, '\[FAIL\]')).Count
    Write-Output ''
    Write-Output '============================================'
    Write-Output ("  AB-DISPLAY PASS=$pass FAIL=$fail")
    Write-Output '============================================'

    # Pass criteria: no failures, and the frame really was compared pixel by pixel
    if ($fail -ne 0) { exit 1 }
    if ($out -notmatch 'pix_bad=0') { Write-Output 'pix_bad not 0 - see transcript'; exit 1 }
    if ($out -notmatch 'errors=0')  { Write-Output 'TB reported errors - see transcript'; exit 1 }
    exit 0
} finally {
    Pop-Location
}
