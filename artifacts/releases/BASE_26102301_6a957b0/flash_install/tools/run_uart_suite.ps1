param([string]$Port='COM6',[Parameter(Mandatory=$true)][string]$OutputRoot,[string]$Scope='post-Flash UART verification')
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$O=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $O){throw 'Fresh evidence directory required'}
$flash=Get-Content -LiteralPath "$root\evidence\flash_program\flash_image.verified.json" -Raw|ConvertFrom-Json
if(-not $flash.accepted -or -not $flash.official_program_and_verify_passed){throw 'No exact Flash approval'}
$archive=Join-Path $root 'validation_tools'
$manifest=(Get-Content -LiteralPath "$archive\host_scripts.sha256.json" -Raw|ConvertFrom-Json).actual_host_scripts_sha256
$scripts=Join-Path $O 'host_scripts';$null=New-Item -ItemType Directory -Path $scripts -Force
$hashes=@{}
foreach($n in @('ready.ps1','configuration.ps1','geometries.ps1','periods.ps1','recovery.ps1','monitor.ps1')){
 $rel=if($n -eq 'monitor.ps1'){'monitor_board_readonly.ps1'}else{'board870_scripts/'+$n}
 $src=Join-Path "$archive\host_scripts" $rel
 $expected=$manifest.PSObject.Properties[$rel].Value
 if(-not $expected -or (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw "Host script identity failed: $rel"}
 Copy-Item -LiteralPath $src -Destination "$scripts\$n"
 $hashes[$n]=(Get-FileHash -LiteralPath "$scripts\$n" -Algorithm SHA256).Hash.ToLowerInvariant()
}
$hashes|ConvertTo-Json|Set-Content -LiteralPath "$O\host_scripts.sha256.json" -Encoding utf8
$log=New-Object IO.StreamWriter((Join-Path $O 'events.jsonl'),$false,(New-Object Text.UTF8Encoding($false)))
function Event([hashtable]$e){$e.utc=[DateTime]::UtcNow.ToString('o');$log.WriteLine(($e|ConvertTo-Json -Compress));$log.Flush()}
function Checked([string]$name,[scriptblock]$action){Event @{kind='stage_started';name=$name};& $action;if($LASTEXITCODE -ne 0){throw ($name+' failed exit='+$LASTEXITCODE)};Event @{kind='stage_passed';name=$name};Write-Output ($name+' PASS')}
try{
 Event @{kind='suite_started';scope=$Scope;no_programming=$true}
 Checked 'ready' { & "$scripts\ready.ps1" -Port $Port -OutDir "$O\ready" -TimeoutSeconds 300 }
 Checked 'configuration_40' { & "$scripts\configuration.ps1" -Port $Port -OutDir "$O\configuration" }
 Checked 'eight_scaler_geometries' { & "$scripts\geometries.ps1" -Port $Port -OutDir "$O\geometries" }
 Checked 'four_carousel_periods' { & "$scripts\periods.ps1" -Port $Port -OutDir "$O\periods" }
 Checked 'two_media_recoveries' { & "$scripts\recovery.ps1" -Port $Port -OutDir "$O\recovery" -TimeoutSeconds 300 }
 Checked 'steady_carousel_70s' { & "$scripts\monitor.ps1" -Port $Port -ExpectedId 0x26102301 -DurationSeconds 70 -PollSeconds 2 -RequireCarousel -ExpectedPeriod 5 -MinimumCarouselTransitions 10 -OutDir "$O\monitor" }
 @{accepted=$true;scope=$Scope;firmware='26102301';source_commit=$flash.source_commit;bit_sha256=$flash.bit_sha256;flash_image_sha256=$flash.new_flash_sha256;serial_tests_passed=$true;no_programming_during_suite=$true;cold_power_cycle_verified=$false;human_cold_power_confirmation_separate=$true;github_uploaded=$false;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath "$O\complete.json" -Encoding utf8
 Event @{kind='suite_passed';cold_power_cycle_verified=$false}
}catch{
 Event @{kind='error';message=$_.Exception.Message}
 @{accepted=$false;error=$_.Exception.Message;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath "$O\failure.json" -Encoding utf8
 throw
}finally{$log.Dispose()}
exit 0
