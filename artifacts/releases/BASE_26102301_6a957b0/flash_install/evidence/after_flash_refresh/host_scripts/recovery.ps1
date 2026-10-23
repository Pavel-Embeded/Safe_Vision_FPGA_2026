param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutDir,[int]$TimeoutSeconds=300)
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
 $script:lastAckFrame=$m.Value
 return $value
}
function Assert-MediaKeyIdentity([uint32]$ExpectedLow,[uint32]$ExpectedHigh,[uint32]$ActualLow,[uint32]$ActualHigh){
 if($ExpectedLow -ne $ActualLow -or $ExpectedHigh -ne $ActualHigh){
  throw ('Recovery changed media keys: expected IDHIGH={0:X8} IDLOW={1:X8}; actual IDHIGH={2:X8} IDLOW={3:X8}' -f $ExpectedHigh,$ExpectedLow,$ActualHigh,$ActualLow)
 }
}
function Read-MediaKeyIdentity([string]$Phase,[int]$Cycle){
 $low=Send 'B:IDLOW?';$lowAck=$script:lastAckFrame
 $high=Send 'B:IDHIGH?';$highAck=$script:lastAckFrame
 $snapshot=@{IDLOW=$low;IDHIGH=$high;slot_keys=@([uint16]($low -band 65535),[uint16]($low -shr 16),[uint16]($high -band 65535),[uint16]($high -shr 16));idlow_ack=$lowAck;idhigh_ack=$highAck}
 Log @{kind='media_key_identity';phase=$Phase;cycle=$Cycle;values=$snapshot}
 return $snapshot
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
try{
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200};PauseRx 100
 if((Send 'B:DIAG=0') -ne 0x26102301){throw 'Unexpected firmware; no recovery command sent'}
 Healthy
 $beforeMedia=Read-MediaKeyIdentity -Phase 'before_recovery' -Cycle -1
 $before=@{};foreach($q in @('A:BRTPC','A:CONTRAST','A:SCALER','A:SCALESEL','C:VOL','C:PERIOD','C:AUTO','C:MENU')){$before[$q]=Send ($q+'?')}
 for($cycle=0;$cycle -lt 2;$cycle++){
  $null=Send 'C:RECOVER=1';$started=$timer.ElapsedMilliseconds;$seenBusy=$false;$ready=$false
  while($timer.ElapsedMilliseconds-$started -lt $TimeoutSeconds*1000){
   $state=Send 'B:RECOVERY?';$cache=Send 'B:CACHE?';$status=Send 'B:STATUS?'
   if($state -ne 0 -or $cache -ne 15){$seenBusy=$true}
   Log @{kind='recovery_state';cycle=$cycle;state=$state;cache=$cache;status=$status}
   if($seenBusy -and $state -eq 0 -and $cache -eq 15 -and $status -eq 7){$ready=$true;break}
   PauseRx 500
  }
  if(-not $ready){throw ('Recovery cycle did not rescan and return READY: '+$cycle)}
  Healthy
  $words=Send 'B:DIAG=8';$rows=Send 'B:DIAG=9'
  if($words -ne 153600 -or $rows -ne 480){throw 'Recovered frame readback not complete'}
  foreach($q in $before.Keys){if((Send ($q+'?')) -ne $before[$q]){throw ('Recovery changed retained configuration '+$q)}}
  $afterMedia=Read-MediaKeyIdentity -Phase 'after_recovery' -Cycle $cycle
  Assert-MediaKeyIdentity $beforeMedia.IDLOW $beforeMedia.IDHIGH $afterMedia.IDLOW $afterMedia.IDHIGH
  Log @{kind='recovery_complete';cycle=$cycle;duration_ms=($timer.ElapsedMilliseconds-$started);observed_busy=$seenBusy;words=$words;rows=$rows;configuration_retained=$true;media_keys_unchanged=$true;media_keys=$afterMedia.slot_keys}
  Write-Output ('Media recovery cycle='+$cycle+' rescan and four-slot integrity PASS')
  PauseRx 1500
 }
 Log @{kind='complete';recovery_cycles=2;four_slots_ready=$true;configuration_retained=$true;media_keys_unchanged=$true;media_keys=$beforeMedia.slot_keys;physical_display_verified=$false;physical_audio_verified=$false};$script:exitCode=0
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()}
exit $script:exitCode
