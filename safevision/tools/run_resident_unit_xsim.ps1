param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/resident_unit_xsim'),
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin'
)
$ErrorActionPreference='Stop'
$RunDir=[IO.Path]::GetFullPath($RunDir)
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$sv=Join-Path $RepoRoot 'safevision';$oldTmp=$env:TMP;$oldTemp=$env:TEMP
try{
 foreach($name in @('board_play_control','resident_row_integrity','file_index_window')){
  $run=Join-Path $RunDir $name
  New-Item -ItemType Directory -Force (Join-Path $run 'tmp')|Out-Null
  $env:TMP=Join-Path $run 'tmp';$env:TEMP=$env:TMP
  $rtl=if($name -eq 'board_play_control'){'platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v'}elseif($name -eq 'file_index_window'){'rtl/storage/file_index.v'}else{'rtl/memory/frame_integrity_guard.v'}
  Push-Location -LiteralPath $run
  try{
   Write-XSimProject -Paths @((Join-Path $sv $rtl)) -Path rtl.prj
   & (Join-Path $XSimBin 'xvlog.bat') -i (Join-Path $sv 'rtl/include') --log rtl.log --file rtl.prj > rtl.console.log 2>&1
   if($LASTEXITCODE){throw 'Resident RTL compilation failed'}
   Write-XSimProject -Paths @((Join-Path $sv "verification/unit/tb_$name.sv")) -Path sim.prj
   & (Join-Path $XSimBin 'xvlog.bat') --sv -i (Join-Path $sv 'rtl/include') --log tb.log --file sim.prj > tb.console.log 2>&1
   if($LASTEXITCODE){throw 'Resident test compilation failed'}
   & (Join-Path $XSimBin 'xelab.bat') "work.tb_$name" -s unit --timescale 1ns/1ps --log elab.log > elab.console.log 2>&1
   if($LASTEXITCODE){throw 'Resident elaboration failed'}
   @('run all','quit')|Set-Content -LiteralPath run.tcl -Encoding ASCII
   & (Join-Path $XSimBin 'xsim.bat') unit -tclbatch run.tcl --log sim.log > sim.console.log 2>&1
   $code=$LASTEXITCODE;$log=Get-Content -LiteralPath sim.log -Raw
   if($code -or $log -notmatch "PASS tb_$name" -or $log -notmatch '\$finish called' -or $log -match '(?im)^\s*(Fatal|ERROR:|FAIL)'){throw "Resident unit failed: $run/sim.log"}
   Write-Output "PASS resident $name"
  }finally{Pop-Location}
 }
}finally{$env:TMP=$oldTmp;$env:TEMP=$oldTemp}
