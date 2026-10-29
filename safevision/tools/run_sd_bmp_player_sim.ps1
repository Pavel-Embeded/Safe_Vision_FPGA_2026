




param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/sd_bmp_player'),
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
    'rtl/common/crc16_ccitt.v','rtl/common/crc7.v',
    'rtl/storage/spi_master.v','rtl/storage/sd_initializer.v','rtl/storage/sd_sector_reader.v',
    'rtl/storage/mbr_parser.v','rtl/storage/fat32_boot_parser.v',
    'rtl/storage/fat32_directory_scanner.v','rtl/storage/fat32_cluster_walker.v',
    'rtl/storage/file_index.v','rtl/storage/file_streamer.v','rtl/storage/sd_bmp_player.v',
    'rtl/media/bmp_parser.v','rtl/media/bmp_unpack.v',
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
  & (Join-Path $ModelSimBin 'vlog.exe') -quiet -sv "+incdir+$inc" `
      (Join-Path $sv 'verification/models/sd_spi_card_model.sv') `
      (Join-Path $sv 'verification/unit/tb_sd_bmp_player.sv')
  if($LASTEXITCODE){ throw 'TB compile failed' }

  $do = if($Waves){'log -r /*; run -all; quit -f'}else{'run -all; quit -f'}
  $log = Join-Path $RunDir 'sd_bmp_player.log'
  & (Join-Path $ModelSimBin 'vsim.exe') -c -quiet -do $do work.tb_sd_bmp_player 2>&1 |
      Tee-Object -FilePath $log
  $text = Get-Content -LiteralPath $log -Raw
  $fails = ([regex]::Matches($text,'\[FAIL\]')).Count
  if($fails -gt 0 -or $text -notmatch 'SD-BMP-PLAYER PASS'){
    throw "sd_bmp_player regression FAILED ($fails [FAIL] lines) - see $log"}
  Write-Output 'PASS sd_bmp_player: full 640x480 BMP from the card model, 307200 pixels exact'
}finally{ Pop-Location }
