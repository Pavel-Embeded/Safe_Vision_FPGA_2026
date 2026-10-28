param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutDir,[int]$DurationSeconds=7200,[int]$ManualTransitions=100,[int]$Recoveries=10)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutDir){throw 'Fresh output directory required'}
$null=New-Item -ItemType Directory -Path $OutDir
$OutDir=(Resolve-Path -LiteralPath $OutDir).Path
$log=New-Object IO.StreamWriter((Join-Path $OutDir 'trace.jsonl'),$false,(New-Object Text.UTF8Encoding($false)))
$raw=[IO.File]::Open((Join-Path $OutDir 'rx.bin'),[IO.FileMode]::CreateNew)
$sp=New-Object IO.Ports.SerialPort($Port,115200,([IO.Ports.Parity]::None),8,([IO.Ports.StopBits]::One))
$sp.DtrEnable=$false;$sp.RtsEnable=$false;$sp.Handshake=[IO.Ports.Handshake]::None;$sp.ReadTimeout=100;$sp.WriteTimeout=1000
$timer=[Diagnostics.Stopwatch]::StartNew();$script:response='';$script:exitCode=1
function Log([hashtable]$fields){$fields.elapsed_ms=$timer.ElapsedMilliseconds;$script:loggedAtMs=$fields.elapsed_ms;$fields.utc=[DateTime]::UtcNow.ToString('o');$log.WriteLine(($fields|ConvertTo-Json -Compress));$log.Flush()}
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
 Log @{kind='tx';body=$body;hex=[BitConverter]::ToString($b).Replace('-','')};$script:lastTxMs=$script:loggedAtMs;$sp.Write($b,0,$b.Length)
 $w=[Diagnostics.Stopwatch]::StartNew();$matchesFound=@()
 while($w.ElapsedMilliseconds -lt 2000){
  ReadRx;$matchesFound=@([regex]::Matches($script:response,'\$(C:ACK=([0-9A-F]{2}),([0-9A-F]{8}))\*([0-9A-F]{2})\r\n'))
  if($matchesFound.Count -gt 0){break};Start-Sleep -Milliseconds 3
 }
 if($matchesFound.Count -ne 1){throw ('Expected exactly one ACK: '+$body)}
 if([regex]::Matches($script:response,'\$C:ACK=').Count -ne 1){throw ('Malformed or unsolicited ACK: '+$body)}
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
function Signed([uint32]$v){if($v -ge 2147483648){return ([int64]$v-4294967296)};return ([int64]$v)}

function Defaults {
 $settings=@(@('A:BRTPC',80),@('A:CONTRAST',128),@('A:ALPHA',160),@('A:SCALER',0),@('A:SCALESEL',0),@('A:FADE',1),@('C:VOL',70),@('C:PERIOD',5),@('C:FIELD',0),@('C:MENU',0),@('C:AUTO',1))
 foreach($pair in $settings){$null=Send ($pair[0]+'='+$pair[1])}
 PauseRx 100
 $actual=@{}
 foreach($pair in $settings){$actual[$pair[0]]=Send ($pair[0]+'?');if($actual[$pair[0]] -ne $pair[1]){throw ('Default readback failed '+$pair[0])}}
 Log @{kind='defaults';values=$actual}
}
function Ticker {
 $position=Send 'B:DIAG=101'
 if(($position -shr 12) -ne 0x544B1 -or ($position -band 0xFFF) -ge 1024){throw 'Invalid ticker signature/position'}
 $sampleMs=$timer.ElapsedMilliseconds;$pos=$position -band 4095
 if($null -ne $script:lastTickMs){
  $dt=$sampleMs-$script:lastTickMs
  $expectedPosition=([int][Math]::Floor($dt*0.0299823633))%1024
  $actualPosition=($pos-$script:lastTickPosition+1024)%1024
  $positionError=($actualPosition-$expectedPosition+1536)%1024-512
  if([Math]::Abs($positionError) -gt 4){throw 'Ticker stopped, reset unexpectedly or ran at the wrong cadence'}
  Log @{kind='ticker_rate';interval_ms=$dt;expected_pixels=$expectedPosition;actual_pixels=$actualPosition;position_error=$positionError}
 }
 $script:lastTickMs=$sampleMs;$script:lastTickPosition=$pos
 Log @{kind='ticker';position=$pos;sample_ms=$sampleMs;period_pixels=1024}
 return $pos
}
$matched=$false;$restored=$false;$script:lastTickMs=$null;$latencies=New-Object 'System.Collections.Generic.List[int]'
try {
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200;expected_id='26102801'};PauseRx 100
 if((Send 'B:DIAG=0') -ne 0x26102801){throw 'Unexpected firmware; no writes sent'}
 $matched=$true;Healthy
 $first=Ticker;PauseRx 2100;$second=Ticker
 $dp=($second-$first+1024)%1024
 if($dp -lt 50 -or $dp -gt 75){throw 'Ticker position stalled or wrong speed'}
 Log @{kind='ticker_cadence';pixels=$dp;accepted=$true}
 $null=Send 'C:AUTO=0';PauseRx 1500
 $slot=Send 'B:SLOT?';$gen=Send 'B:GEN?'
 for($n=0;$n -lt $ManualTransitions;$n++){
  $null=Send 'C:NEXT=1';$request=$script:lastTxMs;PauseRx 1000
  $nowSlot=Send 'B:SLOT?';$nowGen=Send 'B:GEN?';$lat=Send 'B:LATENCY?'
  if($nowSlot -ne (($slot+1)%4) -or $nowGen -ne (($gen+1)%256)){throw 'Accepted NEXT did not commit exactly once'}
  if($lat -eq 65535){throw 'NEXT timing canceled; stale latency is excluded'}
  $latencies.Add([int]$lat);Log @{kind='transition';index=$n;requested_ms=$request;observed_ms=$timer.ElapsedMilliseconds;slot=$nowSlot;generation=$nowGen;latency_ms=$lat}
  $slot=$nowSlot;$gen=$nowGen
  if(($n%10) -eq 0){Healthy;$null=Ticker}
 }
 Healthy
 for($n=0;$n -lt $Recoveries;$n++){
  $null=Ticker;$null=Send 'C:RECOVER=1';$request=$script:lastTxMs
  $busy=$false;$cleared=$false;$done=$false
  while($timer.ElapsedMilliseconds-$request -lt 30000){
   $state=Send 'B:RECOVERY?';$cache=Send 'B:CACHE?';$ready=Send 'B:STATUS?'
   if($state -gt 0 -and $state -lt 5){$busy=$true};if($cache -ne 15){$cleared=$true}
   if($state -eq 5){throw 'Recovery locked'}
   if($busy -and $cleared -and $state -eq 0 -and $cache -eq 15 -and $ready -eq 7){$done=$true;break}
   PauseRx 25
  }
  if(-not $done){throw 'Recovery completion/cache transition missing'}
  $completedMs=$timer.ElapsedMilliseconds;$recoveryMs=$completedMs-$request;Healthy;$null=Ticker
  Log @{kind='recovery';index=$n;request_ms=$request;completed_ms=$completedMs;duration_ms=$recoveryMs;busy=$busy;cache_clear=$cleared;defaults_reset=$false}
  PauseRx 500
 }
 Defaults;$restored=$true;PauseRx 1000;Healthy
 $monitorStart=$timer.ElapsedMilliseconds;$observations=0;$progressGeneration=$null;$progressMs=$monitorStart
 Log @{kind='monitor_started';start_ms=$monitorStart}
 while($timer.ElapsedMilliseconds-$monitorStart -lt 1000*$DurationSeconds){
  Healthy;$null=Ticker
  $values=@{};foreach($q in @('STATUS','SLOT','GEN','EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')){$values[$q]=Send ('B:'+$q+'?')}
  if($values.STATUS -ne 7){throw 'Media not READY'}
  foreach($q in @('EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')){if($values[$q] -ne 0){throw ('Nonzero '+$q)}}
  if($null -eq $progressGeneration){$progressGeneration=$values.GEN;$progressMs=$timer.ElapsedMilliseconds}
  elseif($timer.ElapsedMilliseconds-$progressMs -ge 30000){if($values.GEN -eq $progressGeneration){throw 'Automatic slideshow generation did not advance for30seconds'};$progressGeneration=$values.GEN;$progressMs=$timer.ElapsedMilliseconds}
  Log @{kind='monitor';index=$observations;values=$values;duration_ms=($timer.ElapsedMilliseconds-$monitorStart)};$observations++
  PauseRx 5000
 }
 $duration=$timer.ElapsedMilliseconds-$monitorStart
 $sorted=@($latencies|Sort-Object);$stats=@{}
 if($sorted.Count){
  $lo=[int][Math]::Floor(($sorted.Count-1)/2);$hi=[int][Math]::Floor($sorted.Count/2)
  $stats=@{count=$sorted.Count;minimum_ms=$sorted[0];median_ms=($sorted[$lo]+$sorted[$hi])/2.0;p95_ms=$sorted[[int][Math]::Ceiling(.95*$sorted.Count)-1];maximum_ms=$sorted[-1]}
 }
 Log @{kind='complete';manual_commits=$ManualTransitions;recoveries=$Recoveries;continuous_monitor_ms=$duration;requested_monitor_seconds=$DurationSeconds;observations=$observations;latency=$stats;defaults_restored=$true;physical_display_verified=$false;flash_written=$false}
 @{accepted=$true;manual_commits=$ManualTransitions;recoveries=$Recoveries;continuous_monitor_ms=$duration;latency=$stats;physical_display_verified=$false;flash_written=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $OutDir 'summary.json') -Encoding utf8
 $script:exitCode=0;Write-Output 'TICKER BOARD REGRESSION PASS'
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{
 if($sp.IsOpen -and $matched -and -not $restored){try{Defaults;Log @{kind='failure_restore_attempted'}}catch{Log @{kind='failure_restore_error';message=$_.Exception.Message}}}
 if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()
}
exit $script:exitCode
