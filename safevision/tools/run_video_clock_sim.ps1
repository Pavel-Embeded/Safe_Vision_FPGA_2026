# ASCII only for Windows PowerShell 5.1.
# Usage from the repository after copying to safevision/tools:
# powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_video_clock_sim.ps1
# Override -XSimBin if Vivado is installed elsewhere.
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$XSimBin = 'D:\Xilinx\Vivado\2018.3\bin',
    [string]$TdRoot = 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string]$RunDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'verification\work_video_clock'),
    [string]$VideoTb = (Join-Path $RepoRoot 'safevision\verification\unit\tb_video_timing.sv'),
    [string]$RealFrameTb = (Join-Path $RepoRoot 'safevision\verification\unit\tb_frame_swap_real_frame.sv'),
    [string]$IntegrationTb = (Join-Path $RepoRoot 'safevision\verification\unit\tb_clock_video_subsystem.sv')
)

$ErrorActionPreference = 'Stop'
$includeDir = Join-Path $RepoRoot 'safevision\rtl\include'
$videoRtl = Join-Path $RepoRoot 'safevision\rtl\video\video_timing\video_timing.v'
$resetRtl = Join-Path $RepoRoot 'safevision\platform\anlogic_eg4s20_hx4s20c\rtl\clock\reset_sync.v'
$resetCtrlRtl = Join-Path $RepoRoot 'safevision\platform\anlogic_eg4s20_hx4s20c\rtl\clock\clock_reset_ctrl.v'
$resetTb = Join-Path $RepoRoot 'safevision\verification\unit\tb_clock_reset_ctrl.sv'
$fbmRtl = Join-Path $RepoRoot 'safevision\rtl\memory\frame_buffer_manager.v'
$swapRtl = Join-Path $RepoRoot 'safevision\rtl\memory\frame_swap_ctrl.v'
$swapCdcRtl = Join-Path $RepoRoot 'safevision\rtl\memory\frame_swap_cdc.v'
$swapTb = Join-Path $RepoRoot 'safevision\verification\unit\tb_frame_swap_ctrl.sv'
$platform = Join-Path $RepoRoot 'safevision\platform\anlogic_eg4s20_hx4s20c'
$clockGenRtl = Join-Path $platform 'rtl\clock\clock_gen.v'
$subsystemRtl = Join-Path $platform 'rtl\clock\clock_video_subsystem.v'
$pllSystem = Join-Path $platform 'ip\pll\sv_system_pll.v'
$pllVga = Join-Path $platform 'ip\pll\sv_video_vga_pll.v'
$pllHd = Join-Path $platform 'ip\pll\sv_video_hd_pll.v'
$pllAudio = Join-Path $platform 'ip\pll\sv_audio_pll.v'
$tdPllModel = Join-Path $TdRoot 'sim_release\eg4\eg_phy_pll.v'
$tdClockModel = Join-Path $TdRoot 'sim_release\eg4\eg_logic_clk.v'
$xvlog = Join-Path $XSimBin 'xvlog.bat'
$xelab = Join-Path $XSimBin 'xelab.bat'
$xsim = Join-Path $XSimBin 'xsim.bat'

@($includeDir, $videoRtl, $VideoTb, $resetRtl, $resetCtrlRtl, $resetTb,
  $fbmRtl, $swapRtl, $swapCdcRtl, $swapTb, $RealFrameTb,
  $clockGenRtl, $subsystemRtl, $pllSystem, $pllVga, $pllHd,
  $pllAudio, $tdPllModel, $tdClockModel, $IntegrationTb,
  $xvlog, $xelab, $xsim) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) { throw "Missing required path: $_" }
}

function Invoke-XSimCase {
    param(
        [string]$Name,
        [string]$Top,
        [string[]]$VerilogSources,
        [string[]]$SvSources,
        [string]$PassMarker
    )

    $caseDir = Join-Path $RunDir $Name
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    # Vivado 2018.3 MinGW stalls when TEMP/TMP contains non-ASCII characters.
    # Keep this process's compiler temporary files under its own case directory.
    $caseTempDir = Join-Path $caseDir 'tmp'
    if ($caseTempDir -match '[^\x00-\x7f]') {
        throw "XSim 2018.3 requires an ASCII RunDir: $RunDir"
    }
    New-Item -ItemType Directory -Force -Path $caseTempDir | Out-Null
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    Push-Location $caseDir
    try {
        $env:TEMP = $caseTempDir
        $env:TMP = $caseTempDir
        # RTL and vendor models compile as Verilog; only testbenches use SV.
        & $xvlog -i $includeDir --log xvlog_verilog.log @VerilogSources
        if ($LASTEXITCODE -ne 0) { throw "$Name Verilog compile failed ($LASTEXITCODE)" }
        & $xvlog --sv -i $includeDir --log xvlog_sv.log @SvSources
        if ($LASTEXITCODE -ne 0) { throw "$Name SystemVerilog compile failed ($LASTEXITCODE)" }
        & $xelab "work.$Top" -s "${Top}_sim" --timescale '1ns/1ps' --log xelab.log
        if ($LASTEXITCODE -ne 0) { throw "$Name elaboration failed ($LASTEXITCODE)" }
        & $xsim "${Top}_sim" -runall --log xsim.log
        if ($LASTEXITCODE -ne 0) { throw "$Name simulation failed ($LASTEXITCODE)" }
        $simLog = Get-Content -LiteralPath 'xsim.log' -Raw
        if ($simLog -match '(?im)^\s*(\[FAIL\]|FAIL\b|FATAL:|ERROR:|\[RESULT\].*FAILED)') {
            throw "$Name reported failure; inspect $caseDir\xsim.log"
        }
        if (-not $simLog.Contains($PassMarker)) {
            throw "$Name did not print PASS marker; inspect $caseDir\xsim.log"
        }
        Write-Output "PASS $Name : $caseDir\xsim.log"
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        Pop-Location
    }
}

Invoke-XSimCase -Name 'video_timing' -Top 'tb_video_timing' `
    -VerilogSources @($videoRtl) -SvSources @($VideoTb) `
    -PassMarker 'PASS tb_video_timing:'
Invoke-XSimCase -Name 'clock_reset' -Top 'tb_clock_reset_ctrl' `
    -VerilogSources @($resetRtl, $resetCtrlRtl) -SvSources @($resetTb) `
    -PassMarker 'clock/reset checks: 88 pass, 0 fail'
Invoke-XSimCase -Name 'frame_swap_existing' -Top 'tb_frame_swap_ctrl' `
    -VerilogSources @($fbmRtl, $swapRtl, $swapCdcRtl) -SvSources @($swapTb) `
    -PassMarker '[RESULT] ALL PASS'
Invoke-XSimCase -Name 'frame_swap_real_frame' -Top 'tb_frame_swap_real_frame' `
    -VerilogSources @($swapRtl) -SvSources @($RealFrameTb) `
    -PassMarker 'PASS tb_frame_swap_real_frame:'
Invoke-XSimCase -Name 'clock_video_subsystem' -Top 'tb_clock_video_subsystem' `
    -VerilogSources @($tdClockModel, $tdPllModel, $pllSystem, $pllVga, $pllHd,
                      $pllAudio, $videoRtl, $resetRtl, $resetCtrlRtl,
                      $clockGenRtl, $subsystemRtl) -SvSources @($IntegrationTb) `
    -PassMarker 'PASS tb_clock_video_subsystem:'


