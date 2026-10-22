param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutDir,[int]$DurationSeconds=30,[int]$PollSeconds=20,[uint32]$ExpectedId=0x26101802,[string]$StopFile='')
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
try{
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200;read_only=$true};PauseRx 100
 $id=Send 'B:DIAG=0';if($id -ne $ExpectedId){throw ('Unexpected firmware: '+$id.ToString('X8'))}
 $ready=$false
 while($timer.Elapsed.TotalSeconds -lt $DurationSeconds){
  $status=Send 'B:STATUS?';$cache=Send 'B:CACHE?';$level=Send 'B:LEVEL?';$fault=Send 'B:FAULT?'
  Log @{kind='preload_observation';status=$status;cache=$cache;level=$level;fault=$fault}
  if($status -eq 7 -and $cache -eq 15 -and $level -eq 0){$ready=$true;break}
  PauseRx 500
 }
 if(-not $ready){throw 'Bounded preload wait failed: READY/cacheF/level0 never observed'}
 Healthy
 $auto=Send 'C:AUTO?';$period=Send 'C:PERIOD?'
 @{accepted=$true;ready_ms=$timer.ElapsedMilliseconds;firmware_id=$id;cache=15;status=7;auto=$auto;period=$period;read_only=$true;flash_written=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'ready.json') -Encoding utf8
 Log @{kind='complete';ready_ms=$timer.ElapsedMilliseconds;read_only=$true};$script:exitCode=0
 Write-Output 'READY_CACHEF_HEALTH_PASS'
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()}
exit $script:exitCode
