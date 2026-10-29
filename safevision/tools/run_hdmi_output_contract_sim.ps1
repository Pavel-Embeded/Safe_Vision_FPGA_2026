


param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$VendorRoot,
 [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/hdmi_output_contract_sim')
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim2018.3 requires ASCII RunDir'}
New-Item -ItemType Directory -Force -Path (Join-Path $RunDir 'tmp') | Out-Null
. (Join-Path $PSScriptRoot 'resolve_hdmi_vendor.ps1')
$vend=Resolve-SafeVisionHdmiVendor -VendorRoot $VendorRoot -RepoRoot $RepoRoot -RunDir $RunDir
$sources=@((Join-Path $vend 'hdmi_phy_warpper.v'),(Join-Path $vend 'lane_lvds_10_1.v'),
 (Join-Path $TdRoot 'sim_release/eg4/eg_logic_io.v'),(Join-Path $TdRoot 'sim_release/eg4/eg_phy_glbl.v'))
foreach($f in $sources){if(-not(Test-Path -LiteralPath $f)){throw "Missing actual vendor model $f"}}
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
Push-Location -LiteralPath $RunDir
try{
 $env:TEMP=Join-Path $RunDir 'tmp';$env:TMP=$env:TEMP
 $sources+=Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v'
 $sources+=Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl/hdmi/a_hdmi_output.v'
 $sources+=Join-Path $RepoRoot 'safevision/rtl/video/hdmi_output/hdmi_video_bridge.v'
 $sources+=Join-Path $RepoRoot 'safevision/rtl/video/hdmi_output/hdmi_edid_control.v'
 & (Join-Path $XSimBin 'xvlog.bat') @sources --log rtl.log > rtl.console.log 2>&1
 if($LASTEXITCODE){throw 'Actual PHY compile failed'}
 & (Join-Path $XSimBin 'xvlog.bat')  -d SAFEVISION_HDMI_CONTRACT_MODEL (Join-Path $RepoRoot 'safevision/verification/models/hdmi_encoder_contract_model.v') (Join-Path $RepoRoot 'safevision/verification/unit/tb_a_hdmi_output.v') --log tb.log > tb.console.log 2>&1
 if($LASTEXITCODE){throw 'PHY test compile failed'}
 & (Join-Path $XSimBin 'xelab.bat') work.tb_a_hdmi_output work.glbl -s phy --timescale '1ns/1ps' --log elab.log > elab.console.log 2>&1
 if($LASTEXITCODE){throw 'PHY elaboration failed'}
 & (Join-Path $XSimBin 'xsim.bat') phy -runall --log sim.log > sim.console.log 2>&1
 $code=$LASTEXITCODE;$out=Get-Content -LiteralPath sim.log -Raw
 if($code -ne 0 -or $out -notmatch 'PASS tb_a_hdmi_output' -or $out -notmatch '\$finish called' -or $out -match '(?im)^\s*(Fatal:|FATAL|ERROR:|\[FAIL\])'){throw 'Actual PHY comparison failed'}
 $out -split "`n" | Where-Object {$_ -match '^PASS'}
}finally{Pop-Location;$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
