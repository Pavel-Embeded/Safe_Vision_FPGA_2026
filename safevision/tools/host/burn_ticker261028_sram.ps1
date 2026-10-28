param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$packagePath=(Resolve-Path -LiteralPath $Package).Path
if(-not $packagePath.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package must be inside the selected project'}
if(Test-Path -LiteralPath $OutDir){throw 'Fresh programming evidence directory required'}
$null=New-Item -ItemType Directory -Path $OutDir
$outPath=(Resolve-Path -LiteralPath $OutDir).Path
if($outPath -match '[^\x00-\x7F{}\r\n]' -or $outPath -match '[{}\r\n]'){throw 'Native evidence path must be ASCII without Tcl delimiters'}
$python=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $python -B (Join-Path $project 'safevision\tools\check_ticker_offline261028.py') --repo $project --package $packagePath --run-dir (Join-Path $outPath 'offline')
if($LASTEXITCODE -ne 0){throw 'Copied source, bitstream or full offline evidence rejected; no download attempted'}
$index=Get-Content -LiteralPath (Join-Path $packagePath 'release.index.json') -Raw|ConvertFrom-Json
$offline=Get-Content -LiteralPath (Join-Path $outPath 'offline\verification.json') -Raw|ConvertFrom-Json
if(-not $offline.accepted -or $offline.bit_sha256 -ne $index.bit_sha256 -or $index.expected_firmware_id -ne '26102801'){throw 'Approval identity mismatch'}
$bit=(Resolve-Path -LiteralPath (Join-Path $packagePath $index.bitstream)).Path
if(-not $bit.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase) -or $bit -match '[^\x00-\x7F]' -or $bit -match '[{}\r\n]'){throw 'Unsafe or escaping native bitstream path'}
if((Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash.ToLowerInvariant() -ne $index.bit_sha256){throw 'Bitstream changed after approval'}
$scriptPath=Join-Path $outPath 'download_sram.tcl'
$tcl='set candidate {'+$bit.Replace('\','/')+"}`n"+@'
puts "BW_TICKER_SRAM_BEGIN"
if {[catch {download -bit $candidate -mode jtag -spd 7 -cable 0} err]} {
 puts stderr "BW_TICKER_SRAM_FAILED: $err"
 exit 1
}
puts "BW_TICKER_SRAM_COMPLETED"
exit 0
'@
[IO.File]::WriteAllText($scriptPath,$tcl,[Text.Encoding]::ASCII)
$exe='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\bw_commands_prompt.exe'
$console=Join-Path $outPath 'download.console.log';$started=[DateTime]::UtcNow.ToString('o')
$nativePreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& $exe ($scriptPath.Replace('\','/')) *> $console;$code=$LASTEXITCODE}
finally{$ErrorActionPreference=$nativePreference}
$text=[IO.File]::ReadAllText($console)
$okay=$code -eq 0 -and $text -match 'Chip\s*validation success: EG4S20BG256' -and $text -match 'BW_TICKER_SRAM_COMPLETED' -and $text -match 'finish command "download -bit' -and $text -notmatch '(?im)\bERROR\b|BW_TICKER_SRAM_FAILED|Unknown cable|USB device open error'
@{program_sram_command_succeeded=$okay;process_exit=$code;bitstream=$bit;bit_sha256=$index.bit_sha256;expected_firmware_id='26102801';approval_source_commit=$index.approval_source_commit;started_at_utc=$started;ended_at_utc=[DateTime]::UtcNow.ToString('o');console_sha256=(Get-FileHash -LiteralPath $console -Algorithm SHA256).Hash.ToLowerInvariant();bitwriter_sha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant();flash_written=$false;hardware_function_verified=$false;github_uploaded=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $outPath 'programming.json') -Encoding utf8
if(-not $okay){Get-Content -LiteralPath $console -Tail 20;throw 'SRAM programming command was not confirmed'}
Write-Output 'SRAM command confirmed; actual firmware and functions require UART and display checks.'
