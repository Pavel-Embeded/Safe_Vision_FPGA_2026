param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutDir){throw 'Fresh output directory required'}
$null=New-Item -ItemType Directory -Path $OutDir
$OutDir=(Resolve-Path -LiteralPath $OutDir).Path
$log=New-Object IO.StreamWriter((Join-Path $OutDir 'trace.jsonl'),$false,(New-Object Text.UTF8Encoding($false)))
$raw=[IO.File]::Open((Join-Path $OutDir 'rx.bin'),[IO.FileMode]::CreateNew)
$sp=New-Object IO.Ports.SerialPort($Port,115200,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One))
$sp.DtrEnable=$false;$sp.RtsEnable=$false;$sp.Handshake=[IO.Ports.Handshake]::None;$sp.ReadTimeout=100;$sp.WriteTimeout=1000
$timer=[Diagnostics.Stopwatch]::StartNew();$script:response='';$script:exitCode=1
function Log([hashtable]$fields){$fields.elapsed_ms=$timer.ElapsedMilliseconds;$fields.utc=[DateTime]::UtcNow.ToString('o');$log.WriteLine(($fields|ConvertTo-Json -Compress));$log.Flush()}
function ReadRx {
 while($sp.BytesToRead -gt 0){
  $b=New-Object byte[] ([Math]::Min($sp.BytesToRead,4096));$n=$sp.Read($b,0,$b.Length)
  if($n -lt $b.Length){$b=[byte[]]$b[0..($n-1)]}
  $raw.Write($b,0,$b.Length);$raw.Flush();$t=[Text.Encoding]::ASCII.GetString($b);$script:response+=$t
  Log @{kind='rx';hex=[BitConverter]::ToString($b).Replace('-','');text=$t}
 }
}
function Send([string]$body){
 ReadRx;$script:response=''
 $sum=0;foreach($b in [Text.Encoding]::ASCII.GetBytes($body)){$sum=$sum -bxor $b}
 $f='$'+$body+('*{0:X2}' -f $sum)+"`r`n";$b=[Text.Encoding]::ASCII.GetBytes($f)
 Log @{kind='tx';body=$body;hex=[BitConverter]::ToString($b).Replace('-','')};$sp.Write($b,0,$b.Length)
 $w=[Diagnostics.Stopwatch]::StartNew();$matchesFound=@()
 while($w.ElapsedMilliseconds -lt 2000){
  ReadRx;$matchesFound=@([regex]::Matches($script:response,'\$(C:ACK=([0-9A-F]{2}),([0-9A-F]{8}))\*([0-9A-F]{2})\r\n'))
  if($matchesFound.Count -gt 0){break};Start-Sleep -Milliseconds 3
 }
 if($matchesFound.Count -ne 1){throw ('Expected exactly one ACK: '+$body)}
 $m=$matchesFound[0];$sum=0;foreach($b in [Text.Encoding]::ASCII.GetBytes($m.Groups[1].Value)){$sum=$sum -bxor $b}
 if($sum -ne [Convert]::ToInt32($m.Groups[4].Value,16)){throw ('Bad ACK checksum: '+$body)}
 $code=[Convert]::ToInt32($m.Groups[2].Value,16);$value=[Convert]::ToUInt32($m.Groups[3].Value,16)
 Log @{kind='ack';body=$body;code=$code;value=$value;frame=$m.Value.TrimEnd("`r","`n")}
 if($code -ne 0){throw ('Rejected '+$body+' code='+$code)}
 return $value
}
function Healthy {
 $health=@{}
 foreach($q in @('CACHE','FAULT','LEVEL','WAVFALLBACK','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW')){
  $health[$q]=Send ('B:'+$q+'?')
 }
 if($health.CACHE -ne 15){throw ('Board unhealthy CACHE='+$health.CACHE)}
 foreach($q in @('LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW')){if($health[$q] -ne 0){throw ('Board unhealthy '+$q+'='+$health[$q])}}
 if($health.FAULT -ne 0 -and -not($health.FAULT -eq 7 -and $health.LEVEL -eq 0 -and $health.WAVFALLBACK -gt 0)){throw ('Board unhealthy FAULT='+$health.FAULT)}
 Log @{kind='health';values=$health;wav_info_allowed=($health.FAULT -eq 7)}
}
function PauseRx([int]$milliseconds){$w=[Diagnostics.Stopwatch]::StartNew();while($w.ElapsedMilliseconds -lt $milliseconds){ReadRx;Start-Sleep -Milliseconds 5}}

$restored=$false;$controlsTouched=$false
function State([int]$period) {
 for($attempt=0;$attempt -lt 5;$attempt++){
  $g0=Send 'B:GEN?';$slot=Send 'B:SLOT?';$g1=Send 'B:GEN?'
  if($g0 -eq $g1){$v=@{generation=$g1;slot=$slot;sample_ms=$timer.ElapsedMilliseconds};Log @{kind='period_sample';period=$period;values=$v};return $v}
 }
 throw 'No stable generation/slot snapshot'
}
try{
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200};PauseRx 100
 if((Send 'B:DIAG=0') -ne 0x26102004){throw 'Unexpected firmware; no settings changed'}
 Healthy
 $originalAuto=Send 'C:AUTO?';$originalPeriod=Send 'C:PERIOD?';$fade=Send 'A:FADE?'
 if($fade -ne 1){throw 'This test requires the verified32-frame Fade setting'}
 $controlsTouched=$true;$tested=0
 foreach($period in @(2,5,10,30)){
  $null=Send 'C:AUTO=0';PauseRx 1200;$null=Send ('C:PERIOD='+$period)
  if((Send 'C:PERIOD?') -ne $period){throw 'Period setting readback mismatch'}
  $before=State $period;$null=Send 'C:AUTO=1'
  if((Send 'C:AUTO?') -ne 1){throw 'Auto did not enable'}
  Log @{kind='period_begin';period=$period;generation=$before.generation;slot=$before.slot;fade_frames=32}
  $commits=0;$lastCommitMs=0;$deadline=$timer.ElapsedMilliseconds+4*($period+2)*1000
  while($commits -lt 3){
   PauseRx 100;$now=State $period
   $delta=($now.generation-$before.generation+256)%256
   if($delta -ne 0){
    if($delta -ne 1 -or $now.slot -ne (($before.slot+1)%4)){throw 'Skipped or inconsistent auto commit'}
    $interval=if($commits -gt 0){$now.sample_ms-$lastCommitMs}else{0}
    if($commits -gt 0 -and [Math]::Abs($interval-($period*1000+533.647)) -gt 250){throw ('Dwell/Fade interval mismatch: '+$interval)}
    Log @{kind='period_commit';period=$period;index=$commits;generation=$now.generation;slot=$now.slot;sample_ms=$now.sample_ms;interval_ms=$interval}
    $lastCommitMs=$now.sample_ms;$commits++;Healthy
   }
   $before=$now
   if($timer.ElapsedMilliseconds -gt $deadline){throw 'Auto period timed out'}
  }
  Log @{kind='period_complete';period=$period;commits=$commits;intervals=2};$tested++
 }
 $null=Send 'C:AUTO=0';PauseRx 1200
 $null=Send ('C:PERIOD='+$originalPeriod);$null=Send ('C:AUTO='+$originalAuto);$restored=$true
 if((Send 'C:PERIOD?') -ne $originalPeriod -or (Send 'C:AUTO?') -ne $originalAuto){throw 'Restore readback failed'}
 Healthy;Log @{kind='complete';period_cases=$tested;auto_commits=12;measured_intervals=8;settings_restored=$true;physical_display_verified=$false;physical_audio_verified=$false};$script:exitCode=0
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{
 if($sp.IsOpen -and $controlsTouched -and -not $restored){
  try{$null=Send ('C:PERIOD='+$originalPeriod);$null=Send ('C:AUTO='+$originalAuto);Log @{kind='failure_restore_attempted';settings_restored=$true}}catch{Log @{kind='failure_restore_error';message=$_.Exception.Message}}
 }
 if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()
}
exit $script:exitCode
