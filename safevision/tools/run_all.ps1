




















param(
    [string]$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$ModelSimBin = $env:MSIM_BIN,
    [string]$XSimBin    = 'D:\Xilinx\Vivado\2018.3\bin',
    [string]$TdRoot     = 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string]$PythonExe = 'python',
    [string]$RunRoot = (Join-Path $RepoRoot 'safevision/build/out/all'),
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


$Entries = @(
    @{ N = 'B main regression (23 TBs / 604 assertions)';        S = 'run_sim.ps1';                     T = 'ModelSim' },
    @{ N = 'C control/safety/audio chain (7 TBs)';               S = 'run_c_sim.ps1';                   T = 'ModelSim' },
    @{ N = 'Clock+reset checks (88 checks)';                     S = 'run_clock_sim.ps1';               T = 'ModelSim' },
    @{ N = 'Current B suite on XSim (all current TBS)'; S = 'run_b_xsim_compat.ps1';        T = 'XSim' },
    @{ N = 'Memory protocol suite (7 TBs + negative controls)';   S = 'run_memory_protocol_sim.ps1';     T = 'XSim' },
    @{ N = 'SDRAM loopback app-level (A model)';                 S = 'run_sdram_loopback_sim.ps1';      T = 'XSimOrModelSim' },
    @{ N = 'A stages 1-9 (5 TBs)';                               S = 'run_a_stage1_9_sim.ps1';          T = 'XSim' },
    @{ N = 'A stages 11-15 (9 TBs, end-to-end display)';         S = 'run_a_stage11_15_sim.ps1';        T = 'XSim' },
    @{ N = 'A video pipeline (2 TBs)';                           S = 'run_video_pipeline_sim.ps1';      T = 'XSim' },
    @{ N = 'Clock/video subsystem (5 TBs)';                      S = 'run_video_clock_sim.ps1';         T = 'XSim' },
    @{ N = 'PLL feedback equivalence (git-ref comparison)';      S = 'run_pll_feedback_equivalence.ps1'; T = 'XSim' },
    @{ N = 'A/B display + core BASE/HD + boundary'; S = 'run_ab_display_sim.ps1'; T = 'XSimOrModelSim' },
    @{ N = 'Full card file -> B write -> A display'; S = 'run_card_to_screen_sim.ps1'; T = 'XSimOrModelSim' },
    @{ N = 'A display internal routed STA (base + hd)';          S = 'run_a_display_sta.ps1'; T = 'TD' },
    @{ N = 'A+B assembly + BMP write bridge routed STA'; S = 'run_ab_core_sta.ps1'; T = 'TD' },
    @{ N = 'A stages16-20 unit checks + arbiter equivalence'; S = 'run_a_stage16_20_sim.ps1'; T = 'XSim' },
    @{ N = 'Complete A+B emergency/display BASE/HD, both policies'; S = 'run_a_system_matrix.ps1'; T = 'XSimOrModelSim' },
    @{ N = 'Actual vendor PHY + actual EG ODDR bit comparisons'; S = 'run_hdmi_phy_sim.ps1'; T = 'XSim' },
    @{ N = 'HDMI wrapper port/stream contract only, encrypted encoding unverified'; S = 'run_hdmi_output_contract_sim.ps1'; T = 'XSim' },
    @{ N = 'Complete A portable assembly routed STA'; S = 'run_a_complete_sta.ps1'; T = 'TD' },
    @{ N = 'B physical board STA including unresolved SDRAM hard-IP'; S = 'run_board_sta.ps1'; T = 'TD' },
    @{ N = 'A physical board assembly STA including unresolved SDRAM hard-IP'; S = 'run_a_board_sta.ps1'; T = 'TD' }
)


foreach($selected in $Only){
 if(-not ($Entries | Where-Object {($_.S -eq $selected) -or (($_.S -replace '\.ps1$','') -eq $selected)})){
  throw "Unknown verification selector: $selected"
 }
}
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

        $tokens=$null;$parseErrors=$null
        $ast=[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$parseErrors)
        if($parseErrors.Count){throw "Cannot parse verification script: $script"}
        $names=@($ast.ParamBlock.Parameters | ForEach-Object {$_.Name.VariablePath.UserPath})
        $values=@{RepoRoot=$RepoRoot;ModelSimBin=$ModelSimBin;XSimBin=$XSimBin;
          TdRoot=$TdRoot;PythonExe=$PythonExe;RunDir=(Join-Path $RunRoot $short)}
        $argsForChild=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script)
        foreach($key in @('RepoRoot','ModelSimBin','XSimBin','TdRoot','PythonExe','RunDir')){
          if($names -contains $key -and -not [string]::IsNullOrWhiteSpace($values[$key])){
            $argsForChild+=@(('-'+$key),$values[$key])
          }
        }
        & powershell @argsForChild
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
