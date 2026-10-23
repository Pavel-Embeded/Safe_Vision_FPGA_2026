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
$restored=$false;$controlsTouched=$false;$original=@{}
function RestoreSettings {
 foreach($q in @('A:SCALER','A:SCALESEL','A:FADE','C:PERIOD','C:AUTO')){$null=Send ($q+'='+$original[$q])}
}
try{
 $sp.Open();Log @{kind='opened';port=$Port;baud=115200;dtr=$false;rts=$false};PauseRx 100
 if((Send 'B:DIAG=0') -ne 0x26102301){throw 'Unexpected firmware; no control writes sent'}
 Healthy
 foreach($q in @('A:SCALER','A:SCALESEL','A:FADE','C:PERIOD','C:AUTO')){$original[$q]=Send ($q+'?')}
 $controlsTouched=$true;$null=Send 'C:AUTO=0';$null=Send 'A:FADE=1';PauseRx 2000
 $totalManual=0;$totalAuto=0
 foreach($algorithm in 0..1){foreach($scale in 0..3){
  $null=Send ('A:SCALER='+$algorithm);$null=Send ('A:SCALESEL='+$scale);PauseRx 1200
  if((Send 'A:SCALER?') -ne $algorithm -or (Send 'A:SCALESEL?') -ne $scale -or (Send 'A:FADE?') -ne 1){throw 'Geometry configuration readback differs'}
  $slot=Send 'B:SLOT?';$generation=Send 'B:GEN?'
  Log @{kind='geometry_start';algorithm=$algorithm;scale=$scale;slot=$slot;generation=$generation}
  for($i=0;$i -lt 4;$i++){
   $null=Send 'C:NEXT=1';PauseRx 1800
   $newSlot=Send 'B:SLOT?';$newGeneration=Send 'B:GEN?'
   if($newSlot -ne (($slot+1)%4) -or $newGeneration -ne (($generation+1)%256)){throw 'Geometry Fade NEXT did not commit once'}
   Log @{kind='geometry_next';algorithm=$algorithm;scale=$scale;index=$i;slot=$newSlot;generation=$newGeneration}
   $slot=$newSlot;$generation=$newGeneration;$totalManual++;Healthy
  }
  $null=Send 'C:PERIOD=2';$null=Send 'C:AUTO=1';PauseRx 11000
  $newSlot=Send 'B:SLOT?';$newGeneration=Send 'B:GEN?';$delta=($newGeneration-$generation+256)%256
  if($delta -lt 4 -or $delta -gt 6 -or $newSlot -ne (($slot+$delta)%4)){throw 'Geometry auto generation differs'}
  Log @{kind='geometry_auto';algorithm=$algorithm;scale=$scale;commits=$delta;slot=$newSlot;generation=$newGeneration}
  $totalAuto+=$delta;$null=Send 'C:AUTO=0';PauseRx 1500;Healthy
  Write-Output ('GEOMETRY algorithm='+$algorithm+' scale='+$scale+' fourNEXT/Fade and auto='+$delta+' health=0')
 }}
 RestoreSettings;$restored=$true
 foreach($q in @('A:SCALER','A:SCALESEL','A:FADE','C:PERIOD','C:AUTO')){if((Send ($q+'?')) -ne $original[$q]){throw ('Restore readback failed '+$q)}}
 Healthy
 Log @{kind='complete';combinations=8;manual_fade_commits=$totalManual;auto_commits=$totalAuto;settings_restored=$true;physical_display_verified=$false;physical_audio_verified=$false}
 $script:exitCode=0
}catch{Log @{kind='error';message=$_.Exception.Message};Write-Output $_.Exception.Message}
finally{
 if($sp.IsOpen -and $controlsTouched -and -not $restored){try{RestoreSettings;Log @{kind='failure_restore_attempted'}}catch{Log @{kind='failure_restore_error';message=$_.Exception.Message}}}
 if($sp.IsOpen){$sp.Close()};$sp.Dispose();Log @{kind='closed';exit_code=$script:exitCode};$raw.Dispose();$log.Dispose()
}
exit $script:exitCode
