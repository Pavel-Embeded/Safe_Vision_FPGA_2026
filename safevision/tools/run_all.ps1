# ============================================================================
# run_all.ps1 - SafeVision verification entry-point aggregator.
# ----------------------------------------------------------------------------
# WHY: the project has grown ~12 run_*.ps1 entry points across two toolchains
#      (ModelSim and XSim/Vivado) plus two TD STA flows. Without an aggregator
#      "my part is green" easily means "the machine I ran on could only run half
#      of it". This script runs every entry that CAN run here and reports SKIP -
#      never PASS - for entries whose toolchain is missing.
#
# CONTRACT (important):
#   * Exit 0 ONLY when every entry point PASSed (SKIP counts as not-passed).
#   * With -AllowSkip: exit 0 when FAIL=0, but the SKIP list is still printed
#     and the final line still says INCOMPLETE. Use it for local work only,
#     never as a release gate.
#   * ASCII only: PowerShell 5.1 may read BOM-less scripts as ANSI.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_all.ps1
#   powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_all.ps1 -AllowSkip
#   powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_all.ps1 -Only run_sim
# ============================================================================
param(
    [string]$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$ModelSimBin = $env:MSIM_BIN,
    [string]$XSimBin    = 'D:\Xilinx\Vivado\2018.3\bin',
    [string]$TdRoot     = 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string[]]$Only     = @(),
    [switch]$AllowSkip
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ToolsDir = Join-Path $RepoRoot 'safevision/tools'

function Test-Tool {
    param([string]$Kind)
    switch ($Kind) {
        'ModelSim' {
            if ([string]::IsNullOrWhiteSpace($ModelSimBin)) { return $false }
            return (Test-Path -LiteralPath (Join-Path $ModelSimBin 'vsim.exe'))
        }
        'XSim' {
            return (Test-Path -LiteralPath (Join-Path $XSimBin 'xvlog.bat'))
        }
        'XSimOrModelSim' {
            if (Test-Path -LiteralPath (Join-Path $XSimBin 'xvlog.bat')) { return $true }
            if ([string]::IsNullOrWhiteSpace($ModelSimBin)) { return $false }
            return (Test-Path -LiteralPath (Join-Path $ModelSimBin 'vsim.exe'))
        }
        'TD' {
            return (Test-Path -LiteralPath (Join-Path $TdRoot 'bin'))
        }
        default { return $true }
    }
}

function Show-Tool {
    param([string]$Kind)
    switch ($Kind) {
        'ModelSim'       { if ([string]::IsNullOrWhiteSpace($ModelSimBin)) { return 'MSIM_BIN not set' } else { return $ModelSimBin } }
        'XSim'           { return $XSimBin }
        'XSimOrModelSim' { return "$XSimBin  or  $ModelSimBin" }
        'TD'             { return $TdRoot }
        default          { return '-' }
    }
}

# Name / script / required toolchain / what it covers
$Entries = @(
    @{ N = 'B main regression (23 TBs / 604 assertions)';        S = 'run_sim.ps1';                     T = 'ModelSim' },
    @{ N = 'Clock+reset checks (88 checks)';                     S = 'run_clock_sim.ps1';               T = 'ModelSim' },
    @{ N = 'B compat suite on XSim (18 TBs, A stage1-10 same lib)'; S = 'run_b_xsim_compat.ps1';        T = 'XSim' },
    @{ N = 'Memory protocol suite (7 TBs + negative controls)';   S = 'run_memory_protocol_sim.ps1';     T = 'XSim' },
    @{ N = 'SDRAM loopback app-level (A model)';                 S = 'run_sdram_loopback_sim.ps1';      T = 'XSimOrModelSim' },
    @{ N = 'A stages 1-9 (5 TBs)';                               S = 'run_a_stage1_9_sim.ps1';          T = 'XSim' },
    @{ N = 'A stages 11-15 (9 TBs, end-to-end display)';         S = 'run_a_stage11_15_sim.ps1';        T = 'XSim' },
    @{ N = 'A video pipeline (2 TBs)';                           S = 'run_video_pipeline_sim.ps1';      T = 'XSim' },
    @{ N = 'Clock/video subsystem (5 TBs)';                      S = 'run_video_clock_sim.ps1';         T = 'XSim' },
    @{ N = 'PLL feedback equivalence (git-ref comparison)';      S = 'run_pll_feedback_equivalence.ps1'; T = 'XSim' },
    @{ N = 'A/B display-level chain (real BMP -> screen pixels)'; S = 'run_ab_display_sim.ps1';      T = 'ModelSim' },
    @{ N = 'Card->screen chain (SD card -> FAT32 -> BMP -> RGB565)'; S = 'run_card_to_screen_sim.ps1'; T = 'ModelSim' },
    @{ N = 'A display internal routed STA (base + hd)';          S = 'run_a_display_sta.ps1';           T = 'TD' }
)

Write-Output '============================================================================'
Write-Output ' SafeVision verification entry points'
Write-Output ("  ModelSim : {0}" -f (Show-Tool 'ModelSim'))
Write-Output ("  XSim     : {0}" -f (Show-Tool 'XSim'))
Write-Output ("  TD       : {0}" -f (Show-Tool 'TD'))
Write-Output '============================================================================'

$pass = 0; $fail = 0; $skip = 0
$failed = @(); $skipped = @()

foreach ($e in $Entries) {
    $short = $e.S -replace '\.ps1$', ''
    if ($Only.Count -gt 0 -and ($Only -notcontains $short) -and ($Only -notcontains $e.S)) { continue }

    $script = Join-Path $ToolsDir $e.S
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Output ("[SKIP] {0,-56} script missing: {1}" -f $e.N, $e.S)
        $skip++; $skipped += $e.N; continue
    }
    if (-not (Test-Tool $e.T)) {
        Write-Output ("[SKIP] {0,-56} needs {1} (not found: {2})" -f $e.N, $e.T, (Show-Tool $e.T))
        $skip++; $skipped += $e.N; continue
    }

    Write-Output ''
    Write-Output ("---- RUN  {0}  [{1}]" -f $e.S, $e.N)
    $env:MSIM_BIN = $ModelSimBin
    Push-Location -LiteralPath $ToolsDir
    try {
        & powershell -ExecutionPolicy Bypass -File $script
        $code = $LASTEXITCODE
    } finally { Pop-Location }

    if ($code -eq 0) {
        Write-Output ("[PASS] {0,-56} {1}" -f $e.N, $e.S)
        $pass++
    } else {
        Write-Output ("[FAIL] {0,-56} {1} (exit {2})" -f $e.N, $e.S, $code)
        $fail++; $failed += $e.N
    }
}

Write-Output ''
Write-Output '============================================================================'
Write-Output ("  PASS={0}  FAIL={1}  SKIP={2}" -f $pass, $fail, $skip)
if ($failed.Count -gt 0) {
    Write-Output '  FAILED:'
    foreach ($n in $failed) { Write-Output ("    - {0}" -f $n) }
}
if ($skipped.Count -gt 0) {
    Write-Output '  SKIPPED (NOT verified on this machine):'
    foreach ($n in $skipped) { Write-Output ("    - {0}" -f $n) }
}
if ($fail -eq 0 -and $skip -eq 0) {
    Write-Output '  RESULT: ALL PASS'
    Write-Output '============================================================================'
    exit 0
} elseif ($fail -eq 0 -and $AllowSkip) {
    Write-Output '  RESULT: INCOMPLETE (only the runnable subset passed; -AllowSkip set)'
    Write-Output '============================================================================'
    exit 0
} else {
    Write-Output '  RESULT: INCOMPLETE - not a release gate. Do not report this as "all green".'
    Write-Output '============================================================================'
    exit 1
}
