



param([string]$ModelSimBin = $env:MSIM_BIN)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ModelSimBin)) {
    [Console]::Error.WriteLine('Set MSIM_BIN or pass -ModelSimBin with the ModelSim win64 directory.')
    exit 2
}

$vlib = Join-Path $ModelSimBin 'vlib.exe'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        [Console]::Error.WriteLine("Missing simulator executable: $tool")
        exit 2
    }
}

$sv = Split-Path $PSScriptRoot -Parent
$work = Join-Path $sv 'verification\work_clock'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $vlib work
    if ($LASTEXITCODE -ne 0) { exit 1 }

    $rtl = @(
        (Join-Path $sv 'platform\anlogic_eg4s20_hx4s20c\rtl\clock\reset_sync.v'),
        (Join-Path $sv 'platform\anlogic_eg4s20_hx4s20c\rtl\clock\clock_reset_ctrl.v')
    )
    $tb = Join-Path $sv 'verification\unit\tb_clock_reset_ctrl.sv'
    & $vlog $rtl
    if ($LASTEXITCODE -ne 0) { exit 1 }
    & $vlog -sv $tb
    if ($LASTEXITCODE -ne 0) { exit 1 }

    $result = & $vsim -c -do 'onerror {quit -code 1}; run -all; quit -f' tb_clock_reset_ctrl 2>&1 | Out-String
    Write-Output $result
    if ($LASTEXITCODE -ne 0 -or $result -match '\[FAIL\]' -or
        $result -notmatch 'clock/reset checks: [0-9]+ pass, 0 fail') {
        exit 1
    }
    exit 0
}
finally {
    Pop-Location
}
