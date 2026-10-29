

param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/integrity_header_negative'),
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [ValidatePattern('^[0-9a-f]{40}$')][string]$Baseline='27cb1394506337e3366215e1658e5c3b739202cd'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$sv=Join-Path $RepoRoot 'safevision';$run=[IO.Path]::GetFullPath($RunDir)
if($run -match '[^\x00-\x7f]'){throw 'XSim requires ASCII RunDir'}
New-Item -ItemType Directory -Force (Join-Path $run 'tmp') | Out-Null
$old=@(& git -C $RepoRoot show "${Baseline}:safevision/rtl/memory/frame_integrity_guard.v")
if($LASTEXITCODE){throw 'Audited baseline guard is missing from Git history'}
$guard=Join-Path $run 'old_guard.v'
[IO.File]::WriteAllText($guard,($old -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
$oldTmp=$env:TMP;$oldTemp=$env:TEMP
Push-Location -LiteralPath $run
try{
 $env:TMP=Join-Path $run 'tmp';$env:TEMP=$env:TMP
 Write-XSimProject -Paths @($guard,(Join-Path $sv 'rtl/memory/video_read_dma_checked.v')) -Path rtl.prj
 & (Join-Path $XSimBin 'xvlog.bat') -i (Join-Path $sv 'rtl/include') --log rtl.log --file rtl.prj > rtl.console.log 2>&1
 if($LASTEXITCODE){throw 'Negative control RTL compile failed'}
 Write-XSimProject -Paths @((Join-Path $sv 'verification/unit/tb_frame_integrity.v')) -Path tb.prj
 & (Join-Path $XSimBin 'xvlog.bat')  --log tb.log --file tb.prj > tb.console.log 2>&1
 if($LASTEXITCODE){throw 'Negative control TB compile failed'}
 & (Join-Path $XSimBin 'xelab.bat') work.tb_frame_integrity -s header_negative -generic_top '"HEADER_LATE=1"' --timescale 1ns/1ps --log elab.log > elab.console.log 2>&1
 if($LASTEXITCODE){throw 'Negative control elaboration failed'}
 & (Join-Path $XSimBin 'xsim.bat') header_negative -runall --log sim.log > sim.console.log 2>&1
 $result=Get-Content -LiteralPath sim.log -Raw
 if($result -notmatch 'Fatal: complete top/bottom image in either slot verifies' -or
    $result -match '\[PASS\] FRAME INTEGRITY' -or $result -notmatch '\$finish called'){
  throw 'Old guard did not fail with the expected late-header assertion'
 }
 [ordered]@{verified=$true;baseline=$Baseline;expected_failure='late-header first source address rejected';
  assertion='complete top/bottom image in either slot verifies';old_guard_sha256=(Get-FileHash -LiteralPath $guard -Algorithm SHA256).Hash.ToLower()} |
  ConvertTo-Json | Set-Content -LiteralPath negative.json -Encoding UTF8
 Write-Output 'VERIFIED HEADER NEGATIVE CONTROL: old release rejects a legal late BMP header'
}finally{Pop-Location;$env:TMP=$oldTmp;$env:TEMP=$oldTemp}
