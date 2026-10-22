param(
 [Parameter(Mandatory=$true)][string]$Package,
 [Parameter(Mandatory=$true)][string]$OutDir,
 [ValidateSet('base','hd')][string]$Mode='base'
)
$ErrorActionPreference='Stop'
function Sha256Hex([string]$Path){
 $stream=[IO.File]::OpenRead($Path)
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}
 finally{$stream.Dispose();$algorithm.Dispose()}
}
$python=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if(-not (Test-Path -LiteralPath $python)){throw 'Bundled Python runtime is unavailable'}
$exe='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\bw_commands_prompt.exe'
$project=(Resolve-Path -LiteralPath ('D:\Safe_Vision_FPGA_2026')).Path
$packagePath=(Resolve-Path -LiteralPath $Package).Path
if(-not $packagePath.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Program only the verified user-project package'}
if(Test-Path -LiteralPath $OutDir){throw 'Fresh download evidence directory required'}
& $python -B (Join-Path $packagePath 'verify_payload.py')
if($LASTEXITCODE -ne 0){throw 'Payload/source/raw-STA verification failed; download not attempted'}
$index=Get-Content -LiteralPath (Join-Path $packagePath 'release.index.json') -Raw | ConvertFrom-Json
if(-not $index.offline_acceptance_passed -or $index.profile -ne 'four_features_261020' -or $index.expected_firmware_id -ne '26102004'){throw 'No exact four-feature offline approval'}
$rows=@($index.modes | Where-Object {$_.mode -eq $Mode})
if($rows.Count -ne 1){throw 'Requested mode has no unique approved bitstream'}
$row=$rows[0]
$bit=(Resolve-Path -LiteralPath (Join-Path $packagePath $row.bitstream)).Path
if(-not $bit.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Bitstream escaped package'}
if($bit -match '[{}\r\n]' -or $bit -match '[^\x00-\x7F]'){throw 'Native Tcl requires a safe ASCII artifact path'}
if((Sha256Hex $bit) -ne $row.bit_sha256){throw 'Bitstream SHA mismatch'}
$null=New-Item -ItemType Directory -Path $OutDir
$outPath=(Resolve-Path -LiteralPath $OutDir).Path
$scriptPath=Join-Path $outPath 'download_sram.tcl'
$tcl='set candidate {'+$bit.Replace('\','/')+"}`n"+@'
if {![file isfile $candidate]} {error "Missing strictly approved candidate"}
puts "BW_HANDBOOK_SRAM_BEGIN"
if {[catch {download -bit $candidate -mode jtag -spd 7 -cable 0} err]} {
 puts stderr "BW_HANDBOOK_SRAM_FAILED: $err"
 exit 1
}
puts "BW_HANDBOOK_SRAM_COMPLETED"
exit 0
'@
[IO.File]::WriteAllText($scriptPath,$tcl,[Text.Encoding]::ASCII)
$console=Join-Path $outPath 'download.console.log'
$started=[DateTime]::UtcNow.ToString('o')
$nativePreference=$ErrorActionPreference
try{
 # Windows PowerShell treats native stderr as NativeCommandError. Capture the
 # real process exit and write its receipt before rejecting a failed download.
 $ErrorActionPreference='Continue'
 & $exe ($scriptPath.Replace('\','/')) *> $console
 $code=$LASTEXITCODE
}finally{$ErrorActionPreference=$nativePreference}
$output=[IO.File]::ReadAllText($console)
$okay=$code -eq 0 -and $output -match 'Chip\s*validation success: EG4S20BG256' -and $output -match 'BW_HANDBOOK_SRAM_COMPLETED' -and $output -notmatch 'BW_HANDBOOK_SRAM_FAILED'
@{program_sram_command_succeeded=$okay;mode=$Mode;process_exit=$code;bitstream=$bit;bit_sha256=$row.bit_sha256;expected_firmware_id=$index.expected_firmware_id;approval_source_commit=$index.approval_source_commit;started_at_utc=$started;ended_at_utc=[DateTime]::UtcNow.ToString('o');console_sha256=(Sha256Hex $console);flash_written=$false;hardware_function_verified=$false;github_uploaded=$false} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath 'programming.json') -Encoding utf8
if(-not $okay){Get-Content -LiteralPath $console -Tail 15;throw 'SRAM programming was not confirmed'}
Write-Output 'SRAM programming command confirmed; actual UART identity and function still need verification.'
