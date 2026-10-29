

param(
    [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
    [string]$ModelSimBin=$env:MSIM_BIN,
    [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/sdram_loopback_sim')
)
$ErrorActionPreference='Stop'
$RepoRoot=[IO.Path]::GetFullPath($RepoRoot)
$RunDir=[IO.Path]::GetFullPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim 2018.3 needs ASCII RunDir'}

if(-not [string]::IsNullOrWhiteSpace($ModelSimBin)){
    $script:UseModelSim=$true
}elseif(Test-Path -LiteralPath $XSimBin){
    $script:UseModelSim=$false
}else{
    throw 'Set -ModelSimBin (or MSIM_BIN) to ModelSim, or set -XSimBin to XSim 2018.3.'
}
$platform='safevision/platform/anlogic_eg4s20_hx4s20c'
$top=Join-Path $RepoRoot "$platform/rtl/top_sdram_loopback.v"
$tb=Join-Path $RepoRoot 'safevision/verification/unit/tb_sdram_loopback.v'
if($script:UseModelSim){
    $sources=@(
        (Join-Path $RepoRoot 'safevision/rtl/common/uart_tx.v'),
        (Join-Path $RepoRoot 'safevision/rtl/memory/sdr_pat_gen.v'),
        (Join-Path $RepoRoot "$platform/rtl/clock/reset_sync.v"),
        $top,$tb
    )
}else{
    $sources=@(
        (Join-Path $TdRoot 'sim_release/eg4/eg_logic_clk.v'),
        (Join-Path $TdRoot 'sim_release/eg4/eg_phy_pll.v'),
        (Join-Path $RepoRoot "$platform/ip/pll/sv_system_pll.v"),
        (Join-Path $RepoRoot "$platform/rtl/clock/reset_sync.v"),
        (Join-Path $RepoRoot 'safevision/rtl/common/uart_tx.v'),
        (Join-Path $RepoRoot 'safevision/rtl/memory/sdr_pat_gen.v'),
        $top,$tb
    )
}
foreach($file in ($sources + @($top,$tb))){
    if(-not (Test-Path -LiteralPath $file)){throw "Missing simulation source: $file"}
}
$temp=Join-Path $RunDir 'tmp'
New-Item -ItemType Directory -Force -Path $RunDir,$temp | Out-Null
$savedTemp=$env:TEMP;$savedTmp=$env:TMP
try{
    $env:TEMP=$temp;$env:TMP=$temp
    Push-Location -LiteralPath $RunDir
    try{
        if($script:UseModelSim){
            if(-not (Test-Path -LiteralPath $ModelSimBin)){throw "ModelSim directory not found: $ModelSimBin"}
            $env:PATH += ";$ModelSimBin"
            $libName='sdram_loopback_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff')
            & (Join-Path $ModelSimBin 'vlib.exe') $libName
            if($LASTEXITCODE -ne 0){throw 'ModelSim library creation failed'}
            & (Join-Path $ModelSimBin 'vmap.exe') $libName $libName
            if($LASTEXITCODE -ne 0){throw 'ModelSim library mapping failed'}
            $inc='+incdir+'+(Join-Path $RepoRoot 'safevision/rtl/include').Replace('\\','/')
            $vlogArgs=@('-work',$libName,'+define+SIM_MODEL_SIM_STUB',$inc)+$sources
            & (Join-Path $ModelSimBin 'vlog.exe') @vlogArgs
            if($LASTEXITCODE -ne 0){throw 'ModelSim integrated RTL compile failed'}
            $log=(& (Join-Path $ModelSimBin 'vsim.exe') -c -lib $libName -do 'run -all; quit -f' tb_sdram_loopback 2>&1 | Out-String)
            if($LASTEXITCODE -ne 0 -or $log -match '(?im)^\s*(Fatal:|FATAL|ERROR:)' -or
               -not $log.Contains('PASS tb_sdram_loopback:') -or
               -not $log.Contains('PASS loopback case=6 ')){throw "ModelSim application-level scenarios did not all pass. Output:`n$log"}
            $log -split "`r?`n" | Where-Object {$_ -match 'PASS loopback case=|PASS tb_sdram_loopback:'}
        }else{
            & (Join-Path $XSimBin 'xvlog.bat') --log xvlog.log @sources
            if($LASTEXITCODE -ne 0){throw 'Integrated RTL compile failed'}
            & (Join-Path $XSimBin 'xelab.bat') work.tb_sdram_loopback -s sdram_loopback_sim --timescale '1ns/1ps' --log xelab.log
            if($LASTEXITCODE -ne 0){throw 'Integrated testbench elaboration failed'}
            & (Join-Path $XSimBin 'xsim.bat') sdram_loopback_sim -runall --log xsim.log
            if($LASTEXITCODE -ne 0){throw 'Integrated loopback simulation failed'}
            $log=[IO.File]::ReadAllText((Join-Path $RunDir 'xsim.log'))
            if($log -match '(?im)^\s*(Fatal:|FATAL|ERROR:)' -or
               -not $log.Contains('PASS tb_sdram_loopback:')){throw 'Application-level scenarios did not all pass'}
        }
        Write-Output 'PASS integrated SDRAM application-level regression'
    }finally{Pop-Location}
}finally{$env:TEMP=$savedTemp;$env:TMP=$savedTmp}
Write-Output 'Coverage: 21-bit signature, six loopback/fault scenarios, 115200 baud, 190-byte UART report and bounded report completion.'
Write-Output 'Physical SDRAM controller, DQ, refresh/CAS and AC timing remain unverified by this simulation.'
