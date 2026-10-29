





















param([string]$ModelSimBin = $env:MSIM_BIN)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ModelSimBin)) {
    [Console]::Error.WriteLine('Set MSIM_BIN or pass -ModelSimBin with the ModelSim win64 directory.')
    exit 2
}

$vlib = Join-Path $ModelSimBin 'vlib.exe'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vopt = Join-Path $ModelSimBin 'vopt.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
foreach ($tool in @($vlib, $vlog, $vopt, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        [Console]::Error.WriteLine("Missing simulator executable: $tool")
        exit 2
    }
}

$sv   = Split-Path $PSScriptRoot -Parent
$work = Join-Path $sv 'verification\work_c'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$inc = '+incdir+' + (($sv + '/rtl/include') -replace '\\', '/')

$rtl = @(
    (Join-Path $sv 'rtl\common\sync_fifo.v'),
    (Join-Path $sv 'rtl\common\error_report.v'),
    (Join-Path $sv 'rtl\control\input_sync.v'),
    (Join-Path $sv 'rtl\control\key_debounce.v'),
    (Join-Path $sv 'rtl\control\priority_arbiter.v'),
    (Join-Path $sv 'rtl\control\control_event_queue.v'),
    (Join-Path $sv 'rtl\control\playback_fsm.v'),
    (Join-Path $sv 'rtl\safety\watchdog.v'),
    (Join-Path $sv 'rtl\safety\fault_manager.v'),
    (Join-Path $sv 'rtl\safety\emergency_fsm.v'),
    (Join-Path $sv 'rtl\audio\audio_scheduler.v'),
    (Join-Path $sv 'rtl\audio\alarm_tone_gen.v'),
    (Join-Path $sv 'rtl\audio\audio_priority_arbiter.v')
)

$tbFiles = @(
    (Join-Path $sv 'verification\unit\tb_c_input_sync.sv'),
    (Join-Path $sv 'verification\unit\tb_c_priority_arbiter.sv'),
    (Join-Path $sv 'verification\unit\tb_c_playback_fsm.sv'),
    (Join-Path $sv 'verification\unit\tb_c_emergency_fsm.sv'),
    (Join-Path $sv 'verification\unit\tb_c_watchdog.sv'),
    (Join-Path $sv 'verification\unit\tb_c_fault_manager.sv'),
    (Join-Path $sv 'verification\unit\tb_c_audio.sv')
)

$TBS = @(
    'tb_c_input_sync',
    'tb_c_priority_arbiter',
    'tb_c_playback_fsm',
    'tb_c_emergency_fsm',
    'tb_c_watchdog',
    'tb_c_fault_manager',
    'tb_c_audio'
)

Push-Location $work
try {
    if (Test-Path -LiteralPath 'work') { Remove-Item -Recurse -Force 'work' }
    & $vlib work
    if ($LASTEXITCODE -ne 0) { exit 1 }

    & $vlog $inc $rtl
    if ($LASTEXITCODE -ne 0) { Write-Output 'COMPILE FAILED (RTL)'; exit 1 }

    & $vlog -sv $inc $tbFiles
    if ($LASTEXITCODE -ne 0) { Write-Output 'COMPILE FAILED (TB)'; exit 1 }











    $scratch = $env:TEMP + '\safevision_c_sim'
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $doFile = $scratch + '\run.do'
    Set-Content -LiteralPath $doFile -Encoding ASCII -Value @(
        'onerror {quit -code 1}',
        'run -all',
        'quit -f'
    )

    $total_pass = 0
    $total_fail = 0
    foreach ($tb in $TBS) {
        Write-Output ''
        Write-Output ("=== {0} ===" -f $tb)
        $tbLog = $scratch + '\' + $tb + '.vsim.log'
        $o1 = $scratch + '\vopt.out'; $e1 = $scratch + '\vopt.err'
        $o2 = $scratch + '\vsim.out'; $e2 = $scratch + '\vsim.err'
        $out  = ''
        $code = 1
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $p = Start-Process -FilePath $vopt -ArgumentList @("work.$tb", '-o', "${tb}_o") `
                 -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o1 -RedirectStandardError $e1
            if ($p.ExitCode -ne 0) { Start-Sleep -Milliseconds 800; continue }
            $q = Start-Process -FilePath $vsim -ArgumentList @('-c', '-l', $tbLog, '-do', $doFile, "${tb}_o") `
                 -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o2 -RedirectStandardError $e2
            $code = $q.ExitCode
            if (Test-Path -LiteralPath $tbLog) { $out = Get-Content -LiteralPath $tbLog -Raw } else { $out = '' }
            if ($out -match 'errors=\d+') { break }
            Start-Sleep -Milliseconds 800
        }
        Write-Output $out
        $p = ([regex]::Matches($out, '\[PASS\]')).Count
        $f = ([regex]::Matches($out, '\[FAIL\]')).Count
        $total_pass += $p
        $total_fail += $f
        Write-Output ("  -> PASS={0} FAIL={1} exit={2}" -f $p, $f, $code)
        if ($code -ne 0 -or $f -ne 0) { $total_fail += 1 }
    }

    Write-Output ''
    Write-Output '============================================'
    Write-Output ("  C-chain TOTAL PASS={0} FAIL={1}" -f $total_pass, $total_fail)
    Write-Output '============================================'
    if ($total_fail -ne 0) { exit 1 }
    exit 0
}
finally {
    Pop-Location
}
