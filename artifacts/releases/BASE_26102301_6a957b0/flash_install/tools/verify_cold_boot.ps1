param([string]$Port='COM6',[int]$WaitSeconds=1800)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root ('evidence\cold_boot_'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
$approval=Get-Content -LiteralPath "$root\evidence\flash_program\flash_image.verified.json" -Raw|ConvertFrom-Json
if(-not $approval.accepted){throw 'Missing approved Flash installation record'}
$null=New-Item -ItemType Directory -Path $out
$log=New-Object IO.StreamWriter((Join-Path $out 'power_events.jsonl'),$false,(New-Object Text.UTF8Encoding($false)))
function Event([hashtable]$e){$e.utc=[DateTime]::UtcNow.ToString('o');$log.WriteLine(($e|ConvertTo-Json -Compress));$log.Flush()}
function Present{return @([IO.Ports.SerialPort]::GetPortNames()) -contains $Port}
$clock=[Diagnostics.Stopwatch]::StartNew();$missing=$false;$returned=$false;$gap=0
try{
 if(-not(Present)){throw 'Connect the board UART before starting this capture'}
 Event @{kind='baseline_connected';port=$Port;all_power_removal_requires_human_confirmation=$true}
 Write-Output 'Disconnect ALL power (Type-C, JTAG USB-B, external supply); all LEDs must turn off. Wait at least 10 seconds, reconnect. Do NOT program or reset the board.'
 while($clock.Elapsed.TotalSeconds -lt $WaitSeconds){
  if(Test-Path -LiteralPath "$out\STOP"){throw 'Stopped by operator; no cold-boot acceptance'}
  $now=Present
  if(-not $now -and -not $missing){$missing=$true;$at=$clock.ElapsedMilliseconds;Event @{kind='device_disconnected'}}
  if($now -and $missing){$gap=$clock.ElapsedMilliseconds-$at;if($gap -lt 5000){Event @{kind='too_short_disconnect';absence_ms=$gap};$missing=$false}else{$returned=$true;Event @{kind='device_reconnected';absence_ms=$gap};break}}
  Start-Sleep -Milliseconds 300
 }
 if(-not $returned){throw 'No physical unplug/replug observed; cold boot remains pending'}
 Start-Sleep -Seconds 2
 & "$PSScriptRoot\run_uart_suite.ps1" -Port $Port -OutputRoot "$out\uart" -Scope 'USB reconnect; human full power-removal confirmation required'
 if($LASTEXITCODE -ne 0){throw 'UART suite failed'}
 @{accepted=$true;firmware='26102301';usb_disappearance_and_reappearance_observed=$true;absence_ms=$gap;serial_suite_passed=$true;no_programming_during_test=$true;human_all_power_removal_confirmation_required=$true;cold_power_cycle_verified=$false;physical_display_verified=$false;physical_audio_verified=$false;physical_spectrum_verified=$false;github_uploaded=$false;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$out\serial_after_reconnect.json" -Encoding utf8
 Write-Output "Reconnect serial suite passed. Record the human full-power-off confirmation and actual image/sound/spectrum observations separately. Evidence: $out"
}catch{Event @{kind='incomplete';message=$_.Exception.Message};throw}finally{$log.Dispose()}
exit 0
