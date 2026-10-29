param(
 [ValidateSet('Latest','Previous')][string]$Image='Latest',
 [switch]$Apply,
 [string]$OutDir,
 [string]$ToolPath='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\bw_commands_prompt.exe'
)
$ErrorActionPreference='Stop'
$flash=Split-Path -Parent $PSScriptRoot
$release=Split-Path -Parent $flash
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
if($Image -eq 'Latest'){
 $bit=Join-Path $release 'SafeVision_BASE_75b34e6.bit'
 $expected='1a0cf8cccdb1487b34f70e20eaa333dc106826dbc1d821be99b6a828b80b4083'
}else{
 $bit=Join-Path $flash 'recovery\SafeVision_BASE_6a957b0.bit'
 $expected='95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e'
}
if((Hash $bit) -ne $expected){throw 'Candidate bitstream checksum differs'}
foreach($letter in @('a','b')){
 if((Hash (Join-Path $flash ('before_flash_'+$letter+'.bin'))) -ne 'a5f548e3c02d2315fb17640c08e713fbd9831ceec3090112dc5bfd1a6747ab7a'){throw 'Retained original Flash backup differs'}
}
Write-Output ("Image=$Image; candidate=$bit; SHA256=$expected")
if(-not $Apply){Write-Output 'Preview only. No hardware command issued. Use -Apply -OutDir <new ASCII directory> to install.';exit 0}
if((Hash $ToolPath) -ne '513b024c8c1853825441939c9c51feb0156c2c6c2043f854a39e805c38064401'){throw 'Expected validated TD BitWriter executable'}
if(-not $OutDir){throw 'A new external ASCII output directory is required'}
$OutDir=[IO.Path]::GetFullPath($OutDir)
if($OutDir -match '[^\x00-\x7F]' -or $OutDir -match '[{}\r\n]' -or $OutDir.StartsWith($release.TrimEnd('\','/')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Use an external ASCII path without Tcl braces or line breaks'}
if(Test-Path -LiteralPath $OutDir){throw 'Output directory exists; preserve earlier evidence'}
$candidate=$bit.Replace('\','/')
if($candidate -match '[{}\r\n]'){throw 'Unsafe Tcl candidate path'}
$null=New-Item -ItemType Directory -Path $OutDir
$utf8=New-Object Text.UTF8Encoding($false)
$receipt=@{schema=1;image=$Image;bit_sha256=$expected;tool_sha256=(Hash $ToolPath);started_at_utc=[DateTime]::UtcNow.ToString('o');accepted=$false;cold_power_cycle_verified=$false;stages=@{}}
function Save-Receipt{$receipt|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutDir 'receipt.json') -Encoding utf8}
function Stage([string]$Name,[string]$Body,[string[]]$Markers){
 $tcl=Join-Path $OutDir ($Name+'.tcl');$log=Join-Path $OutDir ($Name+'.console.log')
 $header='if {[read_device_id -cable 0] ne "EG4S20BG256"} {error "Unexpected FPGA"}'
 [IO.File]::WriteAllText($tcl,$header+"`n"+$Body+"`nexit 0`n",$utf8)
 $started=[DateTime]::UtcNow.ToString('o')
 & $ToolPath ($tcl.Replace('\','/')) *> $log
 $code=$LASTEXITCODE;$text=Get-Content -LiteralPath $log -Raw
 $ok=$code -eq 0 -and $text -notmatch '(?im)^\s*(?:SV_FLASH_FAILED|ERROR\b|[A-Z]+-\d+\s*:\s*.*\b(?:failed|error)\b)' -and $text -notmatch 'Unknown cable|USB device open error'
 foreach($marker in $Markers){if(-not $text.Contains($marker)){$ok=$false}}
 $receipt.stages[$Name]=@{accepted=$ok;process_exit=$code;started_at_utc=$started;ended_at_utc=[DateTime]::UtcNow.ToString('o');log_sha256=(Hash $log);tcl_sha256=(Hash $tcl)}
 Save-Receipt
 if(-not $ok){throw ('Flash stage failed; preserve logs: '+$Name)}
 [Console]::WriteLine('PASS '+$Name)
 return $text
}
function Read-Pair([string]$Name,[string]$Prefix){
 $body=''
 foreach($letter in @('a','b')){
  $path=(Join-Path $OutDir ($Prefix+'_'+$letter+'.bin')).Replace('\','/')
  $template=@'
set output {__OUTPUT__}
if {[file exists $output]} {error "Preserve existing capture"}
if {[catch {read_flash -start_addr 0x000000 -length 2097152 -output $output -level 1 -total 1 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
if {![file isfile $output] || [file size $output]!=2097152} {error "Incomplete Flash capture"}
puts "SV_FLASH_READ___LETTER___DONE"
'@
  $body+=$template.Replace('__OUTPUT__',$path).Replace('__LETTER__',$letter.ToUpperInvariant())+"`n"
 }
 $null=Stage $Name $body @('SV_FLASH_READ_A_DONE','SV_FLASH_READ_B_DONE')
 $paths=@('a','b'|ForEach-Object {Join-Path $OutDir ($Prefix+'_'+$_+'.bin')})
 foreach($path in $paths){if((Get-Item -LiteralPath $path).Length -ne 2097152){throw 'Full Flash capture size differs'}}
 if((Hash $paths[0]) -ne (Hash $paths[1])){throw 'Independent Flash captures differ'}
 $receipt[$Prefix]=@{bytes=2097152;sha256=(Hash $paths[0]);independent_reads_equal=$true}
 Save-Receipt
}
Save-Receipt
$probe=Stage '01_probe' 'get_flash_manufacturer -cable 0 -spd 7; puts "SV_FLASH_PROBE_DONE"' @('SV_FLASH_PROBE_DONE')
if($probe -notmatch 'Manufacturer ID\s*:\s*ef\b' -or $probe -notmatch 'Interface type\s*:\s*40\b' -or $probe -notmatch 'Density and Feature\s*:\s*15\b'){throw 'Expected EF4015 Flash not confirmed; no write issued'}
Read-Pair '02_backup' 'before_flash'
foreach($operation in @(@('03_program','program_spi','PROGRAM'),@('04_verify','verify_spi','VERIFY'))){
 $template=@'
set candidate {__BIT__}
if {[catch {download -bit $candidate -mode __MODE__ -spd 7 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
puts "SV_FLASH___MARKER___DONE"
'@
 $body=$template.Replace('__BIT__',$candidate).Replace('__MODE__',$operation[1]).Replace('__MARKER__',$operation[2])
 $text=Stage $operation[0] $body @('SV_FLASH_'+$operation[2]+'_DONE')
 if($text -notmatch ('RUN-1003\s*:\s*finish command "download .* -mode '+$operation[1]+' ')){throw 'Normal download completion missing'}
}
Read-Pair '05_readback' 'after_flash'
$refresh=@'
set candidate {__BIT__}
if {[catch {download -bit $candidate -mode refresh -spd 7 -cable 0} err]} {puts stderr "SV_FLASH_FAILED $err";exit 1}
puts "SV_FLASH_REFRESH_DONE"
'@
$text=Stage '06_refresh' ($refresh.Replace('__BIT__',$candidate)) @('SV_FLASH_REFRESH_DONE')
if($text -notmatch 'RUN-1003\s*:\s*finish command "download .* -mode refresh '){throw 'Normal Flash reload completion missing'}
$receipt.accepted=$true;$receipt.flash_written=$true;$receipt.ended_at_utc=[DateTime]::UtcNow.ToString('o');Save-Receipt
Write-Output ("Flash program, verify, independent full reads and reload passed. Evidence: $OutDir")
