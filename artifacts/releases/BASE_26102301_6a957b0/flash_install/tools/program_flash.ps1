param(
 [ValidateSet('Latest','Previous')][string]$Image='Latest',
 [switch]$Apply,
 [string]$ToolPath='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\bw_commands_prompt.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
if($Image -eq 'Latest'){
 $bit=Join-Path $root 'SafeVision_BASE_6a957b0.bit';$expected='95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e'
}else{
 $bit=Join-Path $root 'recovery\SafeVision_BASE_34462ee.bit';$expected='f5cdfedd128199509f45e038397a650214ff3d3ada426fef3dcb835f9af8f5f9'
}
if((Hash $bit) -ne $expected){throw 'Bitstream hash mismatch'}
foreach($copy in @('a','b')){if((Hash (Join-Path $root "recovery\original_flash_$copy.bin")) -ne '0241f34a8af7288067684f9146f16c4579cd77d433b07d225d341ab076ba3857'){throw 'Original Flash backup damaged'}}
Write-Output ("Image=$Image; verified SHA256=$expected; bit=$bit")
if(-not $Apply){Write-Output 'DRY RUN ONLY. Use -Apply to program, verify, and reload Flash. No hardware command was issued.';exit 0}
if(-not(Test-Path -LiteralPath $ToolPath -PathType Leaf)){throw 'TD BitWriter command-line tool not found'}
$out=Join-Path $root ('evidence\manual_flash_'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
$null=New-Item -ItemType Directory -Path $out
$utf8=New-Object Text.UTF8Encoding($false)
$probe=@'
if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
puts "SV_FLASH_PROBE_BEGIN"
get_flash_manufacturer -cable 0 -spd 7
puts "SV_FLASH_PROBE_DONE"
exit 0
'@
[IO.File]::WriteAllText("$out\probe.tcl",$probe,$utf8)
& $ToolPath ((Join-Path $out 'probe.tcl') -replace '\\','/') *> "$out\probe.log"
$probeExit=$LASTEXITCODE;$probeText=Get-Content -LiteralPath "$out\probe.log" -Raw
if($probeExit -ne 0 -or $probeText -notmatch 'SV_FLASH_PROBE_DONE' -or $probeText -notmatch 'Manufacturer ID\s*:\s*ef\b' -or $probeText -notmatch 'Interface type\s*:\s*40\b' -or $probeText -notmatch 'Density and Feature\s*:\s*15\b' -or $probeText -match '(?im)^\s*(?:ERROR\b|[A-Z]+-\d+\s*:\s*.*\b(?:failed|error)\b)'){throw 'Expected EG4S20BG256 + EF4015 Flash not confirmed; write not issued'}
$tclBit=$bit -replace '\\','/'
if($tclBit -match '[{}\r\n]'){throw 'Unsafe Tcl path'}
$body=@'
if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}
set candidate {__BIT__}
puts "SV_FLASH_PROGRAM_BEGIN"
if {[catch {download -bit $candidate -mode program_spi -spd 7 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
puts "SV_FLASH_PROGRAM_DONE"
if {[catch {download -bit $candidate -mode verify_spi -spd 7 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
puts "SV_FLASH_VERIFY_DONE"
if {[catch {download -bit $candidate -mode refresh -spd 7 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
puts "SV_FLASH_REFRESH_DONE"
exit 0
'@
[IO.File]::WriteAllText("$out\program_verify_refresh.tcl",$body.Replace('__BIT__',$tclBit),$utf8)
& $ToolPath ((Join-Path $out 'program_verify_refresh.tcl') -replace '\\','/') *> "$out\program_verify_refresh.log"
$code=$LASTEXITCODE;$log=Get-Content -LiteralPath "$out\program_verify_refresh.log" -Raw
$ok=$code -eq 0 -and $log -match 'SV_FLASH_PROGRAM_DONE' -and $log -match 'SV_FLASH_VERIFY_DONE' -and $log -match 'SV_FLASH_REFRESH_DONE' -and $log -match 'RUN-1003\s*:\s*finish command "download .* -mode program_spi ' -and $log -match 'RUN-1003\s*:\s*finish command "download .* -mode verify_spi ' -and $log -match 'RUN-1003\s*:\s*finish command "download .* -mode refresh ' -and $log -notmatch '(?im)^\s*(?:SV_FLASH_FAILED|ERROR\b|[A-Z]+-\d+\s*:\s*.*\b(?:failed|error)\b)'
@{accepted=$ok;image=$Image;bit_sha256=$expected;process_exit=$code;tool_sha256=(Hash $ToolPath);log_sha256=(Hash "$out\program_verify_refresh.log");flash_write_requested=$true;cold_power_cycle_verified=$false;github_uploaded=$false;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$out\receipt.json" -Encoding utf8
if(-not $ok){throw "Flash operation not accepted. Preserve $out and inspect logs."}
Write-Output "PROGRAM + VERIFY + REFRESH passed; physical power-cycle and serial acceptance remain separate. Evidence: $out"
exit 0
