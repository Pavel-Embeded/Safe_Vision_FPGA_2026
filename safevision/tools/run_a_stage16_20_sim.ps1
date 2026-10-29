

param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/a_stage16_20_sim'),
 [string[]]$Top=@('tb_memory_arbiter_compact','tb_emergency_command_adapter','tb_emergency_control','tb_emergency_graphics','tb_hdmi_edid_control','tb_hdmi_video_bridge')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=[IO.Path]::GetFullPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim2018.3 requires ASCII RunDir'}
$sourceList=Get-Content -LiteralPath (Join-Path $RepoRoot 'safevision/tools/run_a_stage11_15_sim.ps1') -Raw
$rtl=@([regex]::Matches($sourceList,"'((?:platform|rtl)/[^']+\.v)'") | ForEach-Object {Join-Path $RepoRoot ('safevision/'+$_.Groups[1].Value)})
foreach($p in @('rtl/top/safevision_core/safevision_core.v','rtl/top/safevision_core/a_video_system_core.v',
 'rtl/top/safevision_core/bmp_frame_write_bridge.v','rtl/video/emergency_graphics/emergency_command_adapter.v','rtl/video/emergency_graphics/emergency_control_bridge.v',
 'rtl/video/emergency_graphics/emergency_graphics.v','rtl/video/hdmi_output/hdmi_video_bridge.v','rtl/video/hdmi_output/hdmi_edid_control.v')){
 $rtl+=Join-Path $RepoRoot "safevision/$p"
}
$allowed=@('tb_memory_arbiter_compact','tb_emergency_command_adapter','tb_emergency_control','tb_emergency_graphics','tb_hdmi_edid_control','tb_hdmi_video_bridge')
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
try{
 foreach($case in $Top){
  if($case -notin $allowed){throw "Unknown test $case"}
  $dir=Join-Path $RunDir $case
  New-Item -ItemType Directory -Force -Path (Join-Path $dir 'tmp') | Out-Null
  $env:TEMP=Join-Path $dir 'tmp';$env:TMP=$env:TEMP
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'safevision/assets/fonts/font8x16.mem') -Destination (Join-Path $dir 'font8x16.mem') -Force
  Push-Location -LiteralPath $dir
  try{
   Write-XSimProject -Paths $rtl -Path 'rtl.prj'
   & (Join-Path $XSimBin 'xvlog.bat') -i (Join-Path $RepoRoot 'safevision/rtl/include') --file 'rtl.prj' --log rtl.log > rtl.console.log 2>&1
   if($LASTEXITCODE){throw 'Combined A+B compile failed'}
   & (Join-Path $XSimBin 'xvlog.bat') --sv (Join-Path $RepoRoot "safevision/verification/unit/$case.sv") --log tb.log > tb.console.log 2>&1
   if($LASTEXITCODE){throw "TB compile failed $case"}
   & (Join-Path $XSimBin 'xelab.bat') "work.$case" -s $case --timescale '1ns/1ps' --log elab.log > elab.console.log 2>&1
   if($LASTEXITCODE){throw "Elaboration failed $case"}
   & (Join-Path $XSimBin 'xsim.bat') $case -runall --log sim.log > sim.console.log 2>&1
   $code=$LASTEXITCODE;$log=Get-Content -LiteralPath 'sim.log' -Raw
   if($code -ne 0 -or $log -notmatch "PASS $case" -or $log -notmatch '\$finish called' -or $log -match '(?im)^\s*(Fatal:|FATAL|ERROR:|\[FAIL\])'){throw "Simulation failed $case : $dir"}
   $log -split "`n" | Where-Object {$_ -match '^PASS '}
  }finally{Pop-Location}
 }
 Write-Output "PASS A stages16-20 unit suite: $($Top.Count) selected tests"
}finally{$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
