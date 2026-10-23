$ErrorActionPreference='Stop';$B='D:\Codex\svflash921'
$r=Get-Content -LiteralPath "$B\programming.command.receipt.json" -Raw|ConvertFrom-Json
$text=[IO.File]::ReadAllText("$B\program_verify_flash.console.log")
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
if($r.process_exit -ne 0 -or (Hash "$B\program_verify_flash.console.log") -ne $r.console_sha256){throw 'Actual programming process/log mismatch'}
if($text -notmatch 'FLASH921_PROGRAM_RETURNED' -or $text -notmatch 'FLASH921_VERIFY_RETURNED' -or $text -match 'FLASH921_\w+_FAILED|PRG-\d+\s+ERROR|RUN-\d+\s+ERROR|verification failed|verify fail'){throw 'Official programming/verify did not pass'}
if($text -notmatch 'finish command "program_spi -cable 0 -spd 7 -chip EG4S20BG256"' -or $text -notmatch 'finish command "program -cable 0 -spd 7 -p"'){throw 'Missing completed real native write/verify operations'}
if([regex]::Matches($text,'Chip validation success: EG4S20BG256').Count -ne 2){throw 'Device identity mismatch'}
@{accepted=$true;official_program_spi_completed=$true;official_verify_spi_completed=$true;bit_sha256=$r.bit_sha256;source_commit=$r.source_commit;old_flash_sha256=$r.backup_sha256;console_sha256=$r.console_sha256;flash_written=$true;cold_power_cycle_verified=$false;github_uploaded=$false}|ConvertTo-Json|Set-Content -LiteralPath "$B\programming.verified.json" -Encoding utf8
Write-Output 'Official Flash programming and independent VERIFY_SPI PASS; physical power cycle still pending.'
exit 0
