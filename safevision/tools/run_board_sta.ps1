# HX4S20C HDMI-B board bring-up: synthesize, place, route, STA with real pins.
# Default: no bitstream, timing violation = FAIL (strict gate).
# -Bitgen: also run bitgen. It still REPORTS the violation prominently but does
#   not abort, because that path is the packaged SDRAM hard-IP physical path
#   (dq -> internal pad, cell 100% / net 0%, logic level 0) which user RTL
#   cannot retime and which is judged by measurement. A bitstream produced this
#   way is NOT proof that timing passed.
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/board_verify'),
 [string[]]$Mode=@('base','hd'),
 [switch]$Bitgen
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$oldRepo=$env:SAFEVISION_REPO;$oldOut=$env:SAFEVISION_BOARD_OUT;$oldBit=$env:SAFEVISION_BOARD_BITGEN
try{
 $env:SAFEVISION_REPO=$RepoRoot
 $env:SAFEVISION_BOARD_OUT=$RunDir
 $env:SAFEVISION_BOARD_BITGEN = if($Bitgen){'1'}else{'0'}
 if($Bitgen){ Write-Warning 'Bitgen requested: the SDRAM hard-IP setup path is NOT converged. The bitstream is not proof of timing closure.' }
 foreach($m in $Mode){
  if($m -notin @('base','hd')){throw 'Unknown board mode'}
  $flow=Join-Path $RepoRoot "safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/$m.tcl"
  $console=Join-Path $RunDir "$m.console.log"
  & (Join-Path $TdRoot 'bin/td_commands_prompt.exe') $flow.Replace('\','/') > $console 2>&1
  if($LASTEXITCODE){throw "TD flow failed: $console"}
  $timing=Get-Content -LiteralPath (Join-Path $RunDir "$m/route.timing") -Raw
  $setup=[regex]::Match($timing,'SWNS:\s*([-\d.]+)ns')
  $hold=[regex]::Match($timing,'HWNS:\s*([-\d.]+)ns')
  if(-not $setup.Success -or -not $hold.Success){throw 'Missing final timing status'}
  $s=[double]::Parse($setup.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  $h=[double]::Parse($hold.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  $text=Get-Content -LiteralPath $console -Raw
  if($text -notmatch 'BOARD TD ROUTED' -or $text -match '(BOARD TD FAILED|\bERROR:)'){throw "TD incomplete or error: $console"}

  if($s -ge 0 -and $h -ge 0){
   Write-Output "PASS board routed STA $m : setup=$s ns hold=$h ns; HDMI-B pinned, SDRAM package IP"
  } elseif($Bitgen){
   Write-Warning "Timing violation $m setup=$s ns hold=$h ns (SDRAM hard-IP path) - proceeding because -Bitgen was requested"
   Write-Output "WARN board routed STA $m : setup=$s ns hold=$h ns; VIOLATED, bitgen forced by user"
  } else {
   throw "Timing violation $m setup=$s hold=$h"
  }

  if($Bitgen){
   $bit=Join-Path $RunDir "$m/safevision_top.bit"
   if(-not (Test-Path -LiteralPath $bit)){throw "bitgen did not produce $bit"}
   $sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $bit).Hash.ToLower()
   $len=(Get-Item -LiteralPath $bit).Length
   Write-Output ("BIT $m : {0} bytes  SHA256 {1}" -f $len,$sha)
   Write-Output ("BIT path : {0}" -f $bit)
   Write-Output 'BIT note : programming is a separate, deliberate step (TD downloader); this script never programs hardware.'
  }
 }
}finally{
 $env:SAFEVISION_REPO=$oldRepo;$env:SAFEVISION_BOARD_OUT=$oldOut;$env:SAFEVISION_BOARD_BITGEN=$oldBit
}
