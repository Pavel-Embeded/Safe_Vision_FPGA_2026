
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/a_board_verify'),
 [string[]]$Mode=@('base','hd'),
 [string]$VendorRoot
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$oldRepo=$env:SAFEVISION_REPO;$oldOut=$env:SAFEVISION_A_BOARD_OUT;$oldBit=$env:SAFEVISION_BOARD_BITGEN;$oldVendor=$env:SAFEVISION_HDMI_VENDOR
try{
 $env:SAFEVISION_REPO=$RepoRoot
 $env:SAFEVISION_A_BOARD_OUT=$RunDir
 . (Join-Path $PSScriptRoot 'resolve_hdmi_vendor.ps1')
 $env:SAFEVISION_HDMI_VENDOR=Resolve-SafeVisionHdmiVendor -VendorRoot $VendorRoot -RepoRoot $RepoRoot -RunDir $RunDir
 $env:SAFEVISION_BOARD_BITGEN='0'
 foreach($m in $Mode){
  if($m -notin @('base','hd')){throw 'Unknown board mode'}
  $flow=Join-Path $RepoRoot "safevision/platform/anlogic_eg4s20_hx4s20c/project/a_board_verify/$m.tcl"
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
  if($text -notmatch 'A BOARD TD ROUTED' -or $text -match '(A BOARD TD FAILED|\bERROR:)'){throw "TD incomplete or error: $console"}

  if($s -ge 0 -and $h -ge 0){
   Write-Output "PASS board routed STA $m : setup=$s ns hold=$h ns; HDMI-B pinned, SDRAM package IP"
  } else {
   throw "Timing violation $m setup=$s hold=$h"
  }


 }
}finally{
 $env:SAFEVISION_REPO=$oldRepo;$env:SAFEVISION_A_BOARD_OUT=$oldOut;$env:SAFEVISION_BOARD_BITGEN=$oldBit;$env:SAFEVISION_HDMI_VENDOR=$oldVendor
}
