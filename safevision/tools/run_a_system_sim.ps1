

param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/ab_integration'),
 [ValidateSet('Auto','XSim','ModelSim')][string]$Tool='Auto',
 [ValidateSet('tb_a_video_system_core')]
 [string]$Top='tb_a_video_system_core',
 [ValidateSet(0,1)][int]$Immediate=0,
 [ValidateSet(0,1)][int]$HD=0,
 [ValidateRange(0,8)][int]$SubmitLead=0,
 [ValidateRange(1,4)][int]$SwapCount=1,
 [switch]$Waves
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$haveMsim=$ModelSimBin -and (Test-Path -LiteralPath (Join-Path $ModelSimBin 'vsim.exe'))
if($Tool -eq 'Auto'){if($haveMsim){$Tool='ModelSim'}else{$Tool='XSim'}}
if($Tool -eq 'ModelSim' -and -not $haveMsim){throw 'Configured ModelSim is unavailable'}
if($Tool -eq 'XSim' -and -not (Test-Path -LiteralPath (Join-Path $XSimBin 'xsim.bat'))){throw 'XSim is unavailable'}
$RunDir=[IO.Path]::GetFullPath((Join-Path $RunDir "${Top}_hd${HD}_immediate${Immediate}"))
if($Tool -eq 'XSim' -and $RunDir -match '[^\x00-\x7f]'){throw 'XSim2018.3 requires ASCII RunDir'}
New-Item -ItemType Directory -Force -Path (Join-Path $RunDir 'tmp') | Out-Null
$sourceList=Get-Content -LiteralPath (Join-Path $RepoRoot 'safevision/tools/run_a_stage11_15_sim.ps1') -Raw
$rtl=@([regex]::Matches($sourceList,"'((?:platform|rtl)/[^']+\.v)'") | ForEach-Object {
 Join-Path $RepoRoot ('safevision/'+$_.Groups[1].Value)
})
if($rtl.Count -lt 30){throw 'A+B canonical source list was not found'}
$rtl+=Join-Path $RepoRoot 'safevision/rtl/top/safevision_core/safevision_core.v'
$rtl+=Join-Path $RepoRoot 'safevision/rtl/top/safevision_core/bmp_frame_write_bridge.v'
foreach($p in @('rtl/top/safevision_core/a_video_system_core.v','rtl/video/emergency_graphics/emergency_control_bridge.v','rtl/video/emergency_graphics/emergency_graphics.v')){$rtl+=Join-Path $RepoRoot ('safevision/'+$p)}
$sv=@('models/vendor_ip_stub.v','models/sd_spi_card_model.v','models/ab_frame_sink.v',
 'unit/tb_card_to_screen.v','unit/tb_card_to_display.v',
 'unit/tb_ab_frame_display.v','unit/tb_safevision_core.v','unit/tb_a_video_system_core.v') | ForEach-Object {
 Join-Path $RepoRoot ('safevision/verification/'+$_)
}
foreach($f in @($rtl)+@($sv)){if(-not(Test-Path -LiteralPath $f)){throw "Missing source $f"}}
Copy-Item -LiteralPath (Join-Path $RepoRoot 'safevision/assets/fonts/font8x16.mem') -Destination (Join-Path $RunDir 'font8x16.mem') -Force
$inc=Join-Path $RepoRoot 'safevision/rtl/include'
$isCard=$Top -like 'tb_card*'
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
Push-Location -LiteralPath $RunDir
try{
 $env:TEMP=Join-Path $RunDir 'tmp';$env:TMP=$env:TEMP
 if($Tool -eq 'XSim'){
  Write-XSimProject -Paths $rtl -Path 'rtl.prj'
  & (Join-Path $XSimBin 'xvlog.bat') -d SIM_FAST_TO -i $inc --file 'rtl.prj' --log rtl.log > rtl.console.log 2>&1
  if($LASTEXITCODE){throw 'A+B RTL compile failed'}
  Write-XSimProject -Paths $sv -Path 'sv.prj'
  & (Join-Path $XSimBin 'xvlog.bat')  -d SIM_FAST_TO -i $inc --file 'sv.prj' --log tb.log > tb.console.log 2>&1
  if($LASTEXITCODE){throw 'A+B verification compile failed'}

  $generic=@();if(-not $isCard){$generic=@('-generic_top',('"HD='+$HD+'"'),'-generic_top',('"SUBMIT_LEAD='+$SubmitLead+'"'))}
  if($Top -eq 'tb_a_video_system_core'){$generic+=@('-generic_top',('"SWAPS='+$SwapCount+'"'),'-generic_top',('"IMMEDIATE='+$Immediate+'"'))}
  & (Join-Path $XSimBin 'xelab.bat') "work.$Top" -s $Top --timescale '1ns/1ps' @generic --log elab.log > elab.console.log 2>&1
  if($LASTEXITCODE){throw 'A+B elaboration failed'}
  $plus=@();if($Waves){$plus=@('-testplusarg','WAVES')}
  & (Join-Path $XSimBin 'xsim.bat') $Top -runall @plus --log sim.log > sim.console.log 2>&1
  $code=$LASTEXITCODE;$out=Get-Content -LiteralPath sim.log -Raw
  $finished=$out -match '\$finish called'
 }else{
  & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
  if($LASTEXITCODE){throw 'ModelSim library creation failed'}
  & (Join-Path $ModelSimBin 'vlog.exe') '+define+SIM_FAST_TO' "+incdir+$inc" @rtl > rtl.log 2>&1
  if($LASTEXITCODE){throw 'A+B RTL compile failed'}
  & (Join-Path $ModelSimBin 'vlog.exe')  '+define+SIM_FAST_TO' "+incdir+$inc" @sv > tb.log 2>&1
  if($LASTEXITCODE){throw 'A+B verification compile failed'}
  $generic=@();if(-not $isCard){$generic=@("-gHD=$HD","-gSUBMIT_LEAD=$SubmitLead")}
  if($Top -eq 'tb_a_video_system_core'){$generic+=@('-gSWAPS='+$SwapCount,'-gIMMEDIATE='+$Immediate)}
  $plus=@();if($Waves){$plus=@('+WAVES')}
  & (Join-Path $ModelSimBin 'vsim.exe') -c @generic @plus -do 'run -all; quit -f' "work.$Top" > sim.log 2>&1
  $code=$LASTEXITCODE;$out=Get-Content -LiteralPath sim.log -Raw
  $finished=$out -match '\$finish'
 }
 $out=$out -replace '(?m)^#\s*',''
 if($code -ne 0 -or -not $finished -or $out -match '(?im)^\s*(\[FAIL\]|Fatal:|FATAL|ERROR:|FAILED\b)'){
  throw "A+B simulation failed: $RunDir"
 }
 if($isCard){
  if($out -notmatch 'ALL PASS' -or $out -notmatch 'stream bytes=921654 mismatch=0' -or $out -notmatch 'pixels=307200 bad=0'){
   throw 'Complete card-file/pixel comparisons did not pass'
  }
  if($Top -eq 'tb_card_to_display' -and $out -notmatch '\[DISPLAY\] received=307200 compared=307200 errors=0 commits=1 acks=1'){
   throw 'Card-to-display comparison did not finish'
  }
 }elseif($out -notmatch "\[TB\] $Top done, errors=0 \(pix_ok=\d+ pix_bad=0"){
  throw 'Full display comparison did not finish'
 }
 $out -split "`n" | Where-Object {$_ -match '\[PHASE\]|\[DISPLAY\]|\[TB\].*done|ALL PASS|stream bytes=|pixels='}
 if($out -notmatch '\[SYSTEM\].*applied=2'){throw 'Emergency integration checks did not finish'}
 Write-Output "PASS A SYSTEM INTEGRATION top=$Top HD=$HD lead=$SubmitLead swaps=$SwapCount tool=$Tool logs=$RunDir"
}finally{Pop-Location;$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
