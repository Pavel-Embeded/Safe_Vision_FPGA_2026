
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/ab_core_verify'),
 [string[]]$Mode=@('base','hd')
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$oldRepo=$env:SAFEVISION_REPO;$oldOut=$env:SAFEVISION_AB_CORE_OUT
try{
 $env:SAFEVISION_REPO=$RepoRoot;$env:SAFEVISION_AB_CORE_OUT=$RunDir
 foreach($m in $Mode){
  if($m -notin @('base','hd')){throw 'Unknown STA mode'}
  $flow=Join-Path $RepoRoot "safevision/platform/anlogic_eg4s20_hx4s20c/project/ab_core_verify/$m.tcl"
  $console=Join-Path $RunDir "$m.console.log"
  & (Join-Path $TdRoot 'bin/td_commands_prompt.exe') $flow.Replace('\','/') > $console 2>&1
  if($LASTEXITCODE){throw "TD flow failed: $console"}
  $timing=Get-Content -LiteralPath (Join-Path $RunDir "$m/route.timing") -Raw
  $health=Get-Content -LiteralPath (Join-Path $RunDir "$m/route.check") -Raw
  $setup=[regex]::Match($timing,'SWNS:\s*([-\d.]+)ns')
  $hold=[regex]::Match($timing,'HWNS:\s*([-\d.]+)ns')
  if(-not $setup.Success -or -not $hold.Success){throw 'Missing final timing status'}
  $s=[double]::Parse($setup.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  $h=[double]::Parse($hold.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  if($s -lt 0 -or $h -lt 0){throw "Timing violation $m setup=$s hold=$h"}
  foreach($check in @('no clock','clock definition','invalid constraint','combinational loops','soft fifo timing exception constraints')){
   if($health -notmatch ([regex]::Escape($check)+'\(0\)')){throw "TD health failed $m : $check"}
  }
  $text=Get-Content -LiteralPath $console -Raw
  if($text -notmatch 'AB CORE TD ROUTED' -or $text -match '(CRITICAL-WARNING|AB CORE TD FAILED|\bERROR:)'){throw "TD incomplete or critical warning: $console"}
  Write-Output "PASS A+B core internal routed STA $m : setup=$s ns hold=$h ns; three clocks, bounded CDC; probe external I/O has no board budget"
 }
}finally{$env:SAFEVISION_REPO=$oldRepo;$env:SAFEVISION_AB_CORE_OUT=$oldOut}
