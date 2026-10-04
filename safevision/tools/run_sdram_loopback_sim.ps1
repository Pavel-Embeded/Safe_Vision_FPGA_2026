# Application-level loopback regression; encrypted controller and DQ AC excluded.
param(
    [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$BeforeRef='a1dba93fec8f72e1dd383a2097eb0c5eac96610c',
    [string]$GitExe='git',
    [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
    [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/sdram_loopback_sim')
)
$ErrorActionPreference='Stop'
$RepoRoot=[IO.Path]::GetFullPath($RepoRoot)
$RunDir=[IO.Path]::GetFullPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim 2018.3 needs ASCII RunDir'}
$platform='safevision/platform/anlogic_eg4s20_hx4s20c'
$topRelative="$platform/rtl/top_sdram_loopback.v"
$tb=Join-Path $RepoRoot 'safevision/verification/unit/tb_sdram_loopback.sv'
$sources=@(
    (Join-Path $TdRoot 'sim_release/eg4/eg_logic_clk.v'),
    (Join-Path $TdRoot 'sim_release/eg4/eg_phy_pll.v'),
    (Join-Path $RepoRoot "$platform/ip/pll/sv_system_pll.v"),
    (Join-Path $RepoRoot "$platform/rtl/clock/reset_sync.v"),
    (Join-Path $RepoRoot 'safevision/rtl/common/uart_tx.v')
)
$savedTemp=$env:TEMP;$savedTmp=$env:TMP
try{
    foreach($case in @('corrected','old_pattern_negative_control')){
        $caseDir=Join-Path $RunDir $case
        $temp=Join-Path $caseDir 'tmp'
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $env:TEMP=$temp;$env:TMP=$temp
        $top=Join-Path $RepoRoot $topRelative
        if($case -eq 'old_pattern_negative_control'){
            $oldText=(& $GitExe -C $RepoRoot show "${BeforeRef}:${topRelative}") -join "`n"
            if($LASTEXITCODE -ne 0){throw "Missing negative-control baseline $BeforeRef"}
            $top=Join-Path $caseDir 'old_top_sdram_loopback.v'
            [IO.File]::WriteAllText($top,$oldText,(New-Object Text.UTF8Encoding($false)))
        }
        Push-Location -LiteralPath $caseDir
        try{
            & (Join-Path $XSimBin 'xvlog.bat') --log xvlog.log @sources $top
            if($LASTEXITCODE -ne 0){throw "$case RTL compile failed"}
            & (Join-Path $XSimBin 'xvlog.bat') --sv --log xvlog_tb.log $tb
            if($LASTEXITCODE -ne 0){throw "$case TB compile failed"}
            & (Join-Path $XSimBin 'xelab.bat') work.tb_sdram_loopback -s sdram_loopback_sim --timescale '1ns/1ps' --log xelab.log
            if($LASTEXITCODE -ne 0){throw "$case elaboration failed"}
            $extra=if($case -eq 'old_pattern_negative_control'){@('-testplusarg','SKIP_PATTERN_PROOF')}else{@()}
            & (Join-Path $XSimBin 'xsim.bat') sdram_loopback_sim -runall --log xsim.log @extra
            $simExit=$LASTEXITCODE
            $log=[IO.File]::ReadAllText((Join-Path $caseDir 'xsim.log'))
            if($case -eq 'corrected'){
                if($simExit -ne 0 -or $log -match '(?im)^\s*(Fatal:|FATAL|ERROR:)' -or
                    -not $log.Contains('PASS tb_sdram_loopback:')){throw 'Corrected loopback failed'}
            }else{
                if($log.Contains('PASS tb_sdram_loopback:') -or -not $log.Contains('ADDRESS_ALIAS_ESCAPED')){
                    throw 'Negative control did not expose the old high-address alias bug'
                }
            }
            Write-Output "PASS $case"
        }finally{Pop-Location}
    }
}finally{$env:TEMP=$savedTemp;$env:TMP=$savedTmp}
Write-Output 'PASS loopback application regression and old-pattern negative control; physical SDRAM AC unverified'
