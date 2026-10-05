# ============================================================================
# run_card_to_screen_sim.ps1 - SD-card/FAT32 front half -> RGB565 pixels (ModelSim)
# ----------------------------------------------------------------------------
# Runs tb_card_to_screen: the real storage chain driven from the SD card model,
#
#   sd_spi_card_model -> sd_initializer -> sd_sector_reader (CMD17, shared bus)
#     -> mbr_parser -> fat32_boot_parser -> fat32_directory_scanner (+walker)
#     -> file_index -> file_streamer (+walker) -> bmp_parser -> bmp_unpack
#
# and asserts the RGB565 pixel stream against the bytes placed on the card.
#
# WHY A SEPARATE SCRIPT (not part of run_sim.ps1):
#   It only needs B's own sources + the card model, but it is a long, focused
#   integration run (about 0.76 s of simulated time / ~1800 CMD17 reads), so it
#   is kept out of the fast unit gate. run_all.ps1 runs it too.
#
# Prerequisite: ModelSim. Set MSIM_BIN or pass -ModelSimBin.
# ASCII only: PowerShell 5.1 may read BOM-less scripts as ANSI.
# ============================================================================
param(
    [string]$RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$ModelSimBin = $env:MSIM_BIN,
    [string]$RunDir      = (Join-Path (Split-Path $PSScriptRoot -Parent) 'verification/work_card_to_screen')
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

$vlib = Join-Path $ModelSimBin 'vlib.exe'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
$inc  = Join-Path $RepoRoot 'safevision/rtl/include'

# B storage/media chain + the SD card model (no vendor primitives are used here).
$files = @(
    'verification/models/sd_spi_card_model.sv',
    'rtl/common/crc16_ccitt.v',
    'rtl/common/crc7.v',
    'rtl/storage/spi_master.v',
    'rtl/storage/sd_initializer.v',
    'rtl/storage/sd_sector_reader.v',
    'rtl/storage/mbr_parser.v',
    'rtl/storage/fat32_boot_parser.v',
    'rtl/storage/fat32_directory_scanner.v',
    'rtl/storage/fat32_cluster_walker.v',
    'rtl/storage/file_streamer.v',
    'rtl/storage/file_index.v',
    'rtl/media/bmp_parser.v',
    'rtl/media/bmp_unpack.v'
) | ForEach-Object { Join-Path $RepoRoot "safevision/$_" }

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) { throw "missing source: $f" }
}

Push-Location -LiteralPath $RunDir
try {
    & $vlib work | Out-Null
    Write-Output '=== vlog (RTL + card model) ==='
    & $vlog '+define+SIM_FAST_TO' "+incdir+$inc" $files
    if ($LASTEXITCODE -ne 0) { Write-Output 'COMPILE FAILED (RTL)'; exit 1 }

    Write-Output '=== vlog (tb_card_to_screen) ==='
    & $vlog -sv '+define+SIM_FAST_TO' "+incdir+$inc" (Join-Path $RepoRoot 'safevision/verification/unit/tb_card_to_screen.sv')
    if ($LASTEXITCODE -ne 0) { Write-Output 'COMPILE FAILED (TB)'; exit 1 }

    Write-Output '=== vsim tb_card_to_screen ==='
    $out = & $vsim -c -do 'run -all; quit -f' work.tb_card_to_screen 2>&1 | Out-String
    Write-Output $out

    $pass = ([regex]::Matches($out, '\[PASS\]')).Count
    $fail = ([regex]::Matches($out, '\[FAIL\]')).Count
    Write-Output ''
    Write-Output '============================================'
    Write-Output ("  CARD-TO-SCREEN PASS=$pass FAIL=$fail")
    Write-Output '============================================'

    # Pass criteria: no failed checks, and the comparisons actually ran on the
    # whole file / whole frame.
    if ($fail -ne 0)                 { Write-Output 'failed checks - see transcript'; exit 1 }
    if ($out -notmatch 'stream bytes=921654 mismatch=0') { Write-Output 'stream bytes not fully matched - see transcript'; exit 1 }
    if ($out -notmatch 'pixels=307200 bad=0')            { Write-Output 'pixels not fully matched - see transcript'; exit 1 }
    if ($out -notmatch 'ALL PASS')   { Write-Output 'TB did not report ALL PASS - see transcript'; exit 1 }
    exit 0
} finally {
    Pop-Location
}
