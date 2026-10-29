





param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/bmp_frame_sink'),
 [switch]$Waves
)
$ErrorActionPreference='Stop'
if(-not $ModelSimBin -or -not (Test-Path -LiteralPath (Join-Path $ModelSimBin 'vsim.exe'))){
  throw 'Set MSIM_BIN to the ModelSim win64 directory (needs vsim.exe)'}
$ModelSimBin=(Resolve-Path -LiteralPath $ModelSimBin).Path
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$sv=Join-Path $RepoRoot 'safevision'
$inc=Join-Path $sv 'rtl/include'
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
Push-Location $RunDir
try{
  & (Join-Path $ModelSimBin 'vlib.exe') work | Out-Null
  $rtl=@(
    'rtl/common/crc16_ccitt.v',
    'rtl/memory/frame_address_gen.v','rtl/memory/frame_writer.v',
    'rtl/top/safevision_core/bmp_frame_write_bridge.v',

    'platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_ip.v',
    'platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_eram.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/a_pixel_fifo.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v'
  ) | ForEach-Object { Join-Path $sv $_ }
  foreach($f in $rtl){ if(-not (Test-Path -LiteralPath $f)){ throw "Missing source: $f" } }
  & (Join-Path $ModelSimBin 'vlog.exe') -quiet "+incdir+$inc" @rtl
  if($LASTEXITCODE){ throw 'RTL compile failed' }
  & (Join-Path $ModelSimBin 'vlog.exe') -quiet  "+incdir+$inc" `
      (Join-Path $sv 'verification/unit/tb_bmp_frame_sink.v')
  if($LASTEXITCODE){ throw 'TB compile failed' }

  $do = if($Waves){'log -r /*; run -all; quit -f'}else{'run -all; quit -f'}
  $log = Join-Path $RunDir 'bmp_frame_sink.log'
  & (Join-Path $ModelSimBin 'vsim.exe') -c -quiet -do $do work.tb_bmp_frame_sink 2>&1 |
      Tee-Object -FilePath $log
  $text = Get-Content -LiteralPath $log -Raw
  $fails = ([regex]::Matches($text,'\[FAIL\]')).Count
  if($fails -gt 0 -or $text -notmatch 'BMP-FRAME-SINK PASS'){
    throw "bmp_frame_sink regression FAILED ($fails [FAIL] lines) - see $log"}
  Write-Output 'PASS bmp_frame_sink: async 50/125 MHz, error + timeout + drain + orientation coverage'
}finally{ Pop-Location }
