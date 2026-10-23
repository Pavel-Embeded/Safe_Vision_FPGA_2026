param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutDir,[int]$DurationSeconds=3600,[int]$PollSeconds=20,[uint32]$ExpectedId=0x26101736,[string]$StopFile='',
 [switch]$RequireCarousel,[int]$ExpectedPeriod=5,[int]$MinimumCarouselTransitions=10)
$ErrorActionPreference='Stop'
# Pure validation functions are also exercised offline; none performs I/O.
function New-CarouselTracker([uint32]$Generation,[uint32]$Slot,[long]$NowMs,[int]$PeriodSeconds,[int]$MinimumTransitions){
 if($Generation -gt 255 -or $Slot -gt 3 -or $NowMs -lt 0 -or $PeriodSeconds -notin @(2,5,10,30) -or $MinimumTransitions -lt 1){throw 'Invalid carousel baseline'}
 return @{start_ms=$NowMs;last_ms=$NowMs;last_advance_ms=$NowMs;generation=$Generation;slot=$Slot;observations=1;observed_transitions=0;total_generation_delta=0;period_seconds=$PeriodSeconds;expected_step_ms=($PeriodSeconds*1000+533.647);minimum_transitions=$MinimumTransitions}
}
function Update-CarouselTracker([hashtable]$Tracker,[uint32]$Generation,[uint32]$Slot,[long]$NowMs){
 if($Generation -gt 255 -or $Slot -gt 3 -or $NowMs -le $Tracker.last_ms){throw 'Invalid/nonmonotonic carousel sample'}
 $gap=$NowMs-$Tracker.last_ms;$step=$Tracker.expected_step_ms
 if($gap -ge 255*$step){throw 'Carousel sample gap cannot disambiguate generation wrap'}
 $delta=([int64]$Generation-[int64]$Tracker.generation+256)%256
 if($Slot -ne (($Tracker.slot+$delta)%4)){throw 'Carousel generation/slot sequence differs'}
 if($delta -gt (1+[Math]::Floor(($gap+250)/$step))){throw 'Carousel generation advanced faster than elapsed dwell/Fade budget'}
 if($delta -gt 0){$Tracker.observed_transitions++;$Tracker.total_generation_delta+=$delta;$Tracker.last_advance_ms=$NowMs}
 elseif($NowMs-$Tracker.last_advance_ms -gt 2*$step+1000){throw 'Carousel stopped advancing'}
 $elapsed=$NowMs-$Tracker.start_ms
 if($Tracker.total_generation_delta -gt [Math]::Ceiling($elapsed/$step)+1){throw 'Carousel generation total exceeds elapsed-time budget'}
 $Tracker.last_ms=$NowMs;$Tracker.generation=$Generation;$Tracker.slot=$Slot;$Tracker.observations++
}
function Assert-CarouselComplete([hashtable]$Tracker,[long]$NowMs,[long]$RequiredDurationMs){
 $elapsed=$NowMs-$Tracker.start_ms
 if($RequiredDurationMs -le 0 -or $elapsed -lt $RequiredDurationMs -or $Tracker.last_ms-$Tracker.start_ms -lt $RequiredDurationMs){throw 'Carousel observation duration was insufficient'}
 if($Tracker.observed_transitions -lt $Tracker.minimum_transitions -or $Tracker.observations -lt $Tracker.minimum_transitions+1){throw 'Too few actually observed carousel transitions'}
 $lower=[Math]::Max(0,[Math]::Floor(($elapsed-2000)/$Tracker.expected_step_ms))
 $upper=[Math]::Ceiling($elapsed/$Tracker.expected_step_ms)+1
 if($Tracker.total_generation_delta -lt $lower -or $Tracker.total_generation_delta -gt $upper){throw 'Carousel total does not match actual elapsed dwell/Fade budget'}
 return @{accepted=$true;actual_observation_ms=$elapsed;observations=$Tracker.observations;observed_transitions=$Tracker.observed_transitions;total_generation_delta=$Tracker.total_generation_delta;unobserved_intermediate_commits=($Tracker.total_generation_delta-$Tracker.observed_transitions);minimum_observed_transitions=$Tracker.minimum_transitions;expected_period_seconds=$Tracker.period_seconds;expected_step_ms=$Tracker.expected_step_ms}
}
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
function Stable-CarouselState {
 for($attempt=0;$attempt -lt 5;$attempt++){
  $g0=Send 'B:GEN?';$slot=Send 'B:SLOT?';$g1=Send 'B:GEN?'
  if($g0 -gt 255 -or $g1 -gt 255 -or $slot -gt 3){throw 'Out-of-range actual generation/slot'}
  if($g0 -eq $g1){return @{generation=$g1;slot=$slot;sample_ms=$timer.ElapsedMilliseconds}}
 }
 throw 'No stable generation/slot snapshot'
}
try{
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200;read_only=$true};PauseRx 100
 $id=Send 'B:DIAG=0';if($id -ne $ExpectedId){throw ('Unexpected firmware: '+$id.ToString('X8'))}
 $auto=Send 'C:AUTO?';$period=Send 'C:PERIOD?'
 Write-Output ('ACTUAL AUTO='+$auto+' PERIOD='+$period)
  $carousel=$null;$deadlineMs=[int64]$DurationSeconds*1000;$effectivePoll=$PollSeconds
  if($RequireCarousel){
   if($DurationSeconds -le 0 -or $PollSeconds -le 0 -or $auto -ne 1 -or $period -ne $ExpectedPeriod -or (Send 'A:FADE?') -ne 1){throw 'Carousel requires enabled AUTO, expected period, Fade and positive duration/poll'}
   $baseline=Stable-CarouselState
   $carousel=New-CarouselTracker $baseline.generation $baseline.slot $baseline.sample_ms $ExpectedPeriod $MinimumCarouselTransitions
   $deadlineMs=$baseline.sample_ms+[int64]$DurationSeconds*1000;$effectivePoll=[Math]::Min(2,$PollSeconds)
   Log @{kind='carousel_baseline';generation=$baseline.generation;slot=$baseline.slot;sample_ms=$baseline.sample_ms;expected_period=$ExpectedPeriod;minimum_transitions=$MinimumCarouselTransitions;effective_poll_seconds=$effectivePoll}
  }
 $i=0
  while($timer.ElapsedMilliseconds -lt $deadlineMs -and (-not $StopFile -or -not(Test-Path -LiteralPath $StopFile))){
  $values=@{};foreach($q in @('STATUS','CACHE','FAULT','LEVEL','SLOT','GEN','INTEGRITY','PRESENTATION','VUNDERFLOW','UNDERFLOW','OVERFLOW','EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')){$values[$q]=Send ('B:'+$q+'?')}
  if($values.CACHE -ne 15 -or $values.STATUS -ne 7){throw 'Media left READY/cacheF'}
  foreach($q in @('LEVEL','INTEGRITY','PRESENTATION','VUNDERFLOW','UNDERFLOW','OVERFLOW','EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP')){if($values[$q] -ne 0){throw ('Nonzero '+$q+'='+$values[$q])}}
   if($RequireCarousel){
    if((Send 'C:AUTO?') -ne 1 -or (Send 'C:PERIOD?') -ne $ExpectedPeriod -or (Send 'A:FADE?') -ne 1){throw 'Carousel controls changed during observation'}
    $state=Stable-CarouselState;Update-CarouselTracker $carousel $state.generation $state.slot $state.sample_ms
    $values.GEN=$state.generation;$values.SLOT=$state.slot
    Log @{kind='carousel_observation';sample_ms=$state.sample_ms;observed_transitions=$carousel.observed_transitions;total_generation_delta=$carousel.total_generation_delta;generation=$state.generation;slot=$state.slot}
   }
  Log @{kind='observation';index=$i;auto=$auto;period=$period;values=$values}
  Write-Output ('elapsed_s='+[int]$timer.Elapsed.TotalSeconds+' GEN='+$values.GEN+' SLOT='+$values.SLOT+' counters=0')
   $i++;$next=[Math]::Min($deadlineMs,$timer.ElapsedMilliseconds+$effectivePoll*1000)
   while($timer.ElapsedMilliseconds -lt $next -and (-not $StopFile -or -not(Test-Path -LiteralPath $StopFile))){PauseRx 200}
 }
  if($RequireCarousel){
   if($StopFile -and (Test-Path -LiteralPath $StopFile)){throw 'Required carousel observation stopped early'}
   $state=Stable-CarouselState;Update-CarouselTracker $carousel $state.generation $state.slot $state.sample_ms
   $validation=Assert-CarouselComplete $carousel $state.sample_ms ([int64]$DurationSeconds*1000)
   Log @{kind='carousel_complete';validation=$validation}
  }
 Log @{kind='monitor_duration';duration_ms=$timer.ElapsedMilliseconds;requested_seconds=$DurationSeconds;observations=$i;stopped_for_next_stage=($StopFile -and (Test-Path -LiteralPath $StopFile));physical_display_verified=$false;physical_audio_verified=$false}
 Log @{kind='complete';read_only=$true};$script:exitCode=0
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()}
exit $script:exitCode
