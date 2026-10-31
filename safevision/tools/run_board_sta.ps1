



param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/board_verify'),
 [string[]]$Mode=@('base','hd'),
 [switch]$Bitgen,
 [string]$VendorRoot,
 [string]$Python='python'
)
$ErrorActionPreference='Stop'


$PSNativeCommandUseErrorActionPreference=$false
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
if(-not $Mode.Count){throw 'At least one board mode is required.'}
if(@($Mode | Select-Object -Unique).Count -ne $Mode.Count){throw 'Duplicate board modes are not allowed.'}
foreach($m in $Mode){if($m -notin @('base','hd')){throw "Unknown board mode: $m"}}
$tdExe=Join-Path $TdRoot 'bin/td_commands_prompt.exe'
if(-not(Test-Path -LiteralPath $tdExe)){throw "TD executable missing: $tdExe"}
. (Join-Path $PSScriptRoot 'resolve_python.ps1')
$pythonExe=Resolve-SafeVisionPython -Python $Python
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$oldRepo=$env:SAFEVISION_REPO;$oldOut=$env:SAFEVISION_BOARD_OUT;$oldVendor=$env:SAFEVISION_HDMI_VENDOR
$oldRoute=$env:SAFEVISION_APPROVED_ROUTE_DB;$oldCandidate=$env:SAFEVISION_APPROVED_BIT_FILE;$oldParam=$env:SAFEVISION_APPROVED_BIT_PARAM
function Get-BoardSourceSnapshot {
 $sourceRoots=@((Join-Path $RepoRoot 'safevision/rtl'),
  (Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/rtl'),
  (Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/ip'),
  (Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify'),
  (Join-Path $RepoRoot 'safevision/assets/fonts'),$env:SAFEVISION_HDMI_VENDOR)
 $files=@($sourceRoots | ForEach-Object {
  Get-ChildItem -LiteralPath $_ -Recurse -File | Where-Object {$_.Extension -in @('.v','.v','.vh','.sdc','.tcl','.adc','.mem','.list')}
 })
 $files+=@(Get-Item -LiteralPath (Join-Path $PSScriptRoot 'check_board_timing.py'),(Join-Path $PSScriptRoot 'run_board_sta.ps1'))
 foreach($f in @($files | Sort-Object FullName -Unique)){
  [pscustomobject]@{path=$f.FullName;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()}
 }
}
function Save-BoardManifest($path,$value){$value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8}
try{
 $env:SAFEVISION_REPO=$RepoRoot;$env:SAFEVISION_BOARD_OUT=$RunDir
 . (Join-Path $PSScriptRoot 'resolve_hdmi_vendor.ps1')
 $env:SAFEVISION_HDMI_VENDOR=Resolve-SafeVisionHdmiVendor -VendorRoot $VendorRoot -RepoRoot $RepoRoot -RunDir $RunDir
 $records=@();$rejected=@()

 foreach($m in $Mode){
  $modeOut=Join-Path $RunDir $m
  New-Item -ItemType Directory -Force -Path $modeOut | Out-Null
  $manifestPath=Join-Path $modeOut 'build.manifest.json'
  $before=@(Get-BoardSourceSnapshot)
  if($records.Count -gt 0){
   $firstKeys=@($records[0].record.sources | ForEach-Object {$_.path+'|'+$_.sha256})
   $currentKeys=@($before | ForEach-Object {$_.path+'|'+$_.sha256})
   if(Compare-Object -ReferenceObject $firstKeys -DifferenceObject $currentKeys){throw 'Sources changed between requested board modes. No bitstream generated.'}
  }
  $record=[ordered]@{mode=$m;repo=$RepoRoot;td_root=$TdRoot;python=$pythonExe;
   requested_bitgen=[bool]$Bitgen;
   source_scope='conservative board RTL, IP, include, font, constraints, flow, and checker snapshot';
   sources=$before;source_unchanged=$false;gate_status='NOT_RUN';timing_passed=$false;bit_generated=$false;created_at_utc=[DateTime]::UtcNow.ToString('o')}
  Save-BoardManifest $manifestPath $record
  $flow=Join-Path $RepoRoot "safevision/platform/anlogic_eg4s20_hx4s20c/project/board_verify/$m.tcl"
  $console=Join-Path $RunDir "$m.console.log"
  & $tdExe $flow.Replace('\','/') > $console 2>&1
  if($LASTEXITCODE){throw "TD flow failed: $console"}
  $text=Get-Content -LiteralPath $console -Raw
  if($text -notmatch 'BOARD TD ROUTED' -or $text -match '(BOARD TD FAILED|\bERROR:)'){throw "TD incomplete or error: $console"}
  $after=@(Get-BoardSourceSnapshot)
  $beforeKeys=@($before | ForEach-Object {$_.path+'|'+$_.sha256});$afterKeys=@($after | ForEach-Object {$_.path+'|'+$_.sha256})
  if(Compare-Object -ReferenceObject $beforeKeys -DifferenceObject $afterKeys){
   $record.gate_status='SOURCE_CHANGED';$record['sources_after']=$after
   Save-BoardManifest $manifestPath $record
   throw "Source changed during TD run: $m. Re-run on a stable source snapshot."
  }
  $record.source_unchanged=$true
  $timingPath=Join-Path $modeOut 'route.timing';$checkPath=Join-Path $modeOut 'route.check';$gatePath=Join-Path $modeOut 'timing.gate.json'
  $gateArgs=@((Join-Path $PSScriptRoot 'check_board_timing.py'),'--timing',$timingPath,'--check',$checkPath,'--output',$gatePath)
  $gateText=@(& $pythonExe @gateArgs 2>&1);$gateExit=$LASTEXITCODE
  $gateText | Set-Content -LiteralPath (Join-Path $modeOut 'timing.gate.console.log') -Encoding UTF8
  $gateText | ForEach-Object {Write-Output $_}
  if(-not(Test-Path -LiteralPath $gatePath)){throw "Timing checker produced no manifest: $m"}
  $verdict=Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
  $record.gate_status=$verdict.status;$record.timing_passed=[bool]$verdict.timing_passed;$record['timing_gate']=$gatePath
  $record['reports']=@($timingPath,$checkPath,(Join-Path $modeOut 'route.db') | ForEach-Object {
   [pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLower()}
  })
  Save-BoardManifest $manifestPath $record
  $records+=,[pscustomobject]@{mode=$m;out=$modeOut;manifest=$manifestPath;record=$record;verdict=$verdict}
  if($gateExit -ne 0 -or -not $verdict.gate_accepted){$rejected+=$m}
 }
 if($rejected.Count){throw "Routed timing gate rejected mode(s): $($rejected -join ', '). No bitstream generated. See timing.gate.json."}
 foreach($item in $records){
  $m=$item.mode
  if($item.verdict.timing_passed){Write-Output "PASS board routed STA $m : reported setup/hold/recovery/removal and required clock/constraint health checks accepted."}
  else{Write-Warning "Board $m : routed STA reported negative paths. See timing.gate.json."}
  if(-not $Bitgen){continue}
  $compiledKeys=@($item.record.sources | ForEach-Object {$_.path+'|'+$_.sha256})
  $currentKeys=@(Get-BoardSourceSnapshot | ForEach-Object {$_.path+'|'+$_.sha256})
  if(Compare-Object -ReferenceObject $compiledKeys -DifferenceObject $currentKeys){throw "Sources changed before approved bitgen: $m"}
  foreach($report in $item.record.reports){
   if((Get-FileHash -LiteralPath $report.path -Algorithm SHA256).Hash.ToLower() -ne $report.sha256){throw "Approved route/report changed before bitgen: $($report.path)"}
  }
  $bit=Join-Path $item.out 'safevision_top.bit';$candidate=Join-Path $item.out 'safevision_top.pending.bit'
  if(Test-Path -LiteralPath $candidate){Remove-Item -LiteralPath $candidate -Force}
  $env:SAFEVISION_APPROVED_ROUTE_DB=Join-Path $item.out 'route.db';$env:SAFEVISION_APPROVED_BIT_FILE=$candidate
  $env:SAFEVISION_APPROVED_BIT_PARAM=Join-Path $item.out '.bitgen_param.f'
  $bitgenTcl=Join-Path $item.out 'approved_bitgen.tcl'
  @'
if {[catch {
    import_db [file normalize $::env(SAFEVISION_APPROVED_ROUTE_DB)]
    bitgen -bit [file normalize $::env(SAFEVISION_APPROVED_BIT_FILE)]
    export_bitgen_param -file [file normalize $::env(SAFEVISION_APPROVED_BIT_PARAM)]
} err]} {puts stderr "BOARD APPROVED BITGEN FAILED: $err";exit 1}
puts "BOARD APPROVED BITGEN DONE"
exit 0
'@ | Set-Content -LiteralPath $bitgenTcl -Encoding ASCII
  $bitConsole=Join-Path $item.out 'bitgen.console.log'
  & $tdExe $bitgenTcl.Replace('\','/') > $bitConsole 2>&1
  if($LASTEXITCODE){throw "Approved bitgen failed: $bitConsole"}
  $bitText=Get-Content -LiteralPath $bitConsole -Raw
  if($bitText -notmatch 'BOARD APPROVED BITGEN DONE' -or $bitText -match '(BOARD APPROVED BITGEN FAILED|\bERROR:)'){throw "Bitgen incomplete or error: $bitConsole"}
  if(-not(Test-Path -LiteralPath $candidate) -or (Get-Item -LiteralPath $candidate).Length -eq 0){throw "Bitgen produced no candidate: $candidate"}
  Move-Item -LiteralPath $candidate -Destination $bit -Force
  $item.record.bit_generated=$true
  $item.record['bitstream']=[ordered]@{path=$bit;bytes=(Get-Item -LiteralPath $bit).Length;
   sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $bit).Hash.ToLower();timing_passed=[bool]$item.verdict.timing_passed}
  Save-BoardManifest $item.manifest $item.record
  Write-Output "BIT $m : $bit SHA256 $($item.record.bitstream.sha256)"
Write-Output 'BIT note: this script never programs hardware.'
 }
}finally{
 $env:SAFEVISION_REPO=$oldRepo;$env:SAFEVISION_BOARD_OUT=$oldOut;$env:SAFEVISION_HDMI_VENDOR=$oldVendor
 $env:SAFEVISION_APPROVED_ROUTE_DB=$oldRoute;$env:SAFEVISION_APPROVED_BIT_FILE=$oldCandidate;$env:SAFEVISION_APPROVED_BIT_PARAM=$oldParam
}
