# Slow SD writes must not leave SDRAM read outputs masked by DQM.
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/sdram_dqm_xsim'),
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [int[]]$ReadLatencies=@(1,4,7,11,32,64),
 [string]$AdapterPath='',
 [switch]$ExpectOldFailure
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$sv=Join-Path $RepoRoot 'safevision'
if(!$AdapterPath){$AdapterPath=Join-Path $sv 'platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v'}
$oldTmp=$env:TMP;$oldTemp=$env:TEMP
try {
 foreach($lat in $ReadLatencies){
  $run=[IO.Path]::GetFullPath((Join-Path $RunDir "lat_$lat"))
  if($run -match '[^\x00-\x7f]'){throw 'XSim requires ASCII RunDir'}
  New-Item -ItemType Directory -Force (Join-Path $run 'tmp')|Out-Null
  $env:TMP=Join-Path $run 'tmp';$env:TEMP=$env:TMP
  Push-Location -LiteralPath $run
  try {
   Write-XSimProject -Paths @($AdapterPath) -Path rtl.prj
   & (Join-Path $XSimBin 'xvlog.bat') -i (Join-Path $sv 'rtl/include') --log rtl.log --file rtl.prj > rtl.console.log 2>&1
   if($LASTEXITCODE){throw 'DQM RTL compilation failed'}
   Write-XSimProject -Paths @((Join-Path $sv 'verification/models/board_memory_contract_model.sv'),(Join-Path $sv 'verification/unit/tb_sdram_read_dqm.sv')) -Path sim.prj
   & (Join-Path $XSimBin 'xvlog.bat') --sv -i (Join-Path $sv 'rtl/include') --log tb.log --file sim.prj > tb.console.log 2>&1
   if($LASTEXITCODE){throw 'DQM test compilation failed'}
   & (Join-Path $XSimBin 'xelab.bat') work.tb_sdram_read_dqm -generic_top ('"RD_LAT={0}"' -f $lat) -s dqm -debug typical --timescale 1ns/1ps --log elab.log > elab.console.log 2>&1
   if($LASTEXITCODE){throw 'DQM elaboration failed'}
   @('run all','quit')|Set-Content -LiteralPath run.tcl -Encoding ASCII
   & (Join-Path $XSimBin 'xsim.bat') dqm -tclbatch run.tcl --log sim.log > sim.console.log 2>&1
   $simExit=$LASTEXITCODE;$log=Get-Content -LiteralPath sim.log -Raw
   if($ExpectOldFailure){
    if($log -notmatch 'ACTUAL=fea8a821' -or $log -notmatch 'SDRAM_READ_MASK_STUCK_F' -or $log -match 'DQM_PROTOCOL|timeout|watchdog') {throw 'Old-code negative control did not reproduce the board signature'}
    Write-Output "EXPECTED FAILURE old adapter LAT=${lat}: CRC=FEA8A821"
   }else{
    if($simExit -or $log -notmatch 'PASS tb_sdram_read_dqm' -or $log -notmatch '\$finish called' -or $log -match '(?im)^\s*(Fatal|ERROR:|FAIL)'){throw "DQM regression failed: $run/sim.log"}
    Write-Output "PASS DQM LAT=${lat}: CRC=0D968558"
   }
  }finally{Pop-Location}
 }
}finally{$env:TMP=$oldTmp;$env:TEMP=$oldTemp}
