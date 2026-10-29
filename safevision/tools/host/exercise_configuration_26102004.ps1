param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutDir,[ValidateRange(1,1000)][int]$ManualTransitions=8)
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
function Signed([uint32]$v){if($v -ge 2147483648){return ([int64]$v-4294967296)};return ([int64]$v)}
$restored=$false;$firmwareMatched=$false
function Defaults {
 foreach($pair in @(@('A:BRTPC',80),@('A:CONTRAST',128),@('A:ALPHA',160),@('A:SCALER',0),@('A:SCALESEL',0),@('A:FADE',1),@('C:VOL',70),@('C:PERIOD',5),@('C:FIELD',0),@('C:MENU',0),@('C:AUTO',1))){
  $null=Send ($pair[0]+'='+$pair[1])
 }
}
try{
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200;dtr=$false;rts=$false};PauseRx 100
 if((Send 'B:DIAG=0') -ne 0x26102004){throw 'Unexpected firmware; no configuration writes sent'}
 $firmwareMatched=$true
 Healthy


 foreach($pair in @(@('A:BRTPC',80),@('A:BRIGHT',60),@('A:CONTRAST',128),@('A:SCALESEL',0),@('C:VOL',70),@('C:PERIOD',5),@('C:AUTO',1),@('C:MENU',0))){
  $actual=Signed (Send ($pair[0]+'?'));if($actual -ne $pair[1]){throw ('Wrong startup default '+$pair[0])}
  Log @{kind='default_case';name=$pair[0];actual=$actual;expected=$pair[1]}
 }
 $null=Send 'C:AUTO=0';$count=0
 foreach($value in @(0,5,50,80,95,100)){
  $null=Send ('A:BRTPC='+$value);PauseRx 200
  if((Send 'A:BRTPC?') -ne $value -or (Signed (Send 'A:BRIGHT?')) -ne (2*$value-100)){throw 'Percentage-to-offset mapping differs'}
  Healthy;Log @{kind='configuration_case';name='A:BRTPC';requested=$value;actual=$value;raw_offset=(2*$value-100)};$count++
 }
 $cases=@(@('A:CONTRAST',64),@('A:CONTRAST',128),@('A:CONTRAST',255),@('A:ALPHA',0),@('A:ALPHA',128),@('A:ALPHA',255),
 @('A:FADE',0),@('A:FADE',1),@('C:VOL',0),@('C:VOL',10),@('C:VOL',70),@('C:VOL',100),
 @('C:PERIOD',2),@('C:PERIOD',5),@('C:PERIOD',10),@('C:PERIOD',30),@('C:MENU',1),
 @('C:FIELD',0),@('C:FIELD',1),@('C:FIELD',2),@('C:FIELD',3),@('C:FIELD',4),@('C:FIELD',5),@('C:FIELD',6),@('C:FIELD',7),@('C:MENU',0))
 foreach($case in $cases){
  $q=[string]$case[0];$value=[int]$case[1];$null=Send ($q+'='+$value);PauseRx 200
  $actual=Signed (Send ($q+'?'));if($actual -ne $value){throw ('Readback differs '+$q)}
  Healthy;Log @{kind='configuration_case';name=$q;requested=$value;actual=$actual};$count++
 }
 $null=Send 'A:BRTPC=80';$null=Send 'A:CONTRAST=128';$null=Send 'A:ALPHA=160'
 foreach($algorithm in @(0,1)){
  $null=Send ('A:SCALER='+$algorithm)
  foreach($scale in @(0,1,2,3)){
   $null=Send ('A:SCALESEL='+$scale);PauseRx 1200
   if((Send 'A:SCALESEL?') -ne $scale -or (Send 'A:SCALER?') -ne $algorithm){throw 'Scale/algorithm readback differs'}
   Healthy;Log @{kind='configuration_case';name='scaler_geometry';algorithm=$algorithm;scale=$scale};$count++
  }
 }
 Defaults;$restored=$true;PauseRx 1000;Healthy
 Log @{kind='complete';configuration_cases=$count;defaults_restored=$true;physical_display_verified=$false;physical_audio_verified=$false};$script:exitCode=0
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{
 if($sp.IsOpen -and $firmwareMatched -and -not $restored){
  try{Defaults;Log @{kind='failure_restore_attempted';settings_restored=$true}}catch{Log @{kind='failure_restore_error';message=$_.Exception.Message}}
 }
 if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()
}
exit $script:exitCode
