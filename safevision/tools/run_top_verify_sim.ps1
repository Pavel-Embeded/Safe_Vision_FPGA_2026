






param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/top_verify'),
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



$sourceList=Get-Content -LiteralPath (Join-Path $sv 'tools/run_a_stage11_15_sim.ps1') -Raw
$rtl=@([regex]::Matches($sourceList,"'((?:platform|rtl)/[^']+\.v)'") | ForEach-Object {
  Join-Path $sv $_.Groups[1].Value
})
if($rtl.Count -lt 30){ throw 'canonical A source list not found' }


$extra=@(
  'rtl/memory/frame_integrity_guard.v',
  'rtl/memory/video_read_dma_checked.v',
  'platform/anlogic_eg4s20_hx4s20c/rtl/board_display_guard.v',
  'rtl/video/emergency_graphics/emergency_graphics.v',
  'rtl/top/safevision_core/safevision_core.v',
  'rtl/top/safevision_core/bmp_frame_write_bridge.v',
  'rtl/storage/sd_bmp_player.v',
  'rtl/video/hdmi_output/hdmi_video_bridge.v',
  'platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v',
  'platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v'
) | ForEach-Object { Join-Path $sv $_ }
$rtl=@($rtl)+@($extra)

foreach($f in $rtl){ if(-not (Test-Path -LiteralPath $f)){ throw "Missing source: $f" } }

$sim=@(
  'verification/models/vendor_ip_stub.v',
  'verification/models/top_ip_stub.v',
  'verification/models/sd_spi_card_model.v',
  'verification/unit/tb_safevision_top.v'
) | ForEach-Object { Join-Path $sv $_ }
foreach($f in $sim){ if(-not (Test-Path -LiteralPath $f)){ throw "Missing source: $f" } }



Copy-Item -LiteralPath (Join-Path $sv 'assets/fonts/font8x16.mem') -Destination (Join-Path $RunDir 'font8x16.mem') -Force

Push-Location $RunDir
try{
  & (Join-Path $ModelSimBin 'vlib.exe') work > vlib.log 2>&1
  & (Join-Path $ModelSimBin 'vlog.exe') -quiet '+define+SIM_FAST_TO' "+incdir+$inc" @rtl > rtl.log 2>&1
  if($LASTEXITCODE){ Get-Content -LiteralPath (Join-Path $RunDir 'rtl.log') | Select-Object -Last 25; throw 'RTL compile failed' }
  & (Join-Path $ModelSimBin 'vlog.exe') -quiet  '+define+SIM_FAST_TO' "+incdir+$inc" @sim > tb.log 2>&1
  if($LASTEXITCODE){ Get-Content -LiteralPath (Join-Path $RunDir 'tb.log') | Select-Object -Last 25; throw 'TB compile failed' }

  $do = if($Waves){'log -r /*; run -all; quit -f'}else{'run -all; quit -f'}
  $log = Join-Path $RunDir 'safevision_top.log'
  & (Join-Path $ModelSimBin 'vsim.exe') -c -quiet -do $do work.tb_safevision_top 2>&1 |
      Tee-Object -FilePath $log
  $text = Get-Content -LiteralPath $log -Raw
  $fails = ([regex]::Matches($text,'\[FAIL\]')).Count
  if($fails -gt 0 -or $text -notmatch 'SAFEVISION-TOP PASS'){
    throw "safevision_top bring-up FAILED ($fails [FAIL] lines) - see $log"}
  Write-Output 'PASS safevision_top: reset/PLL/SDRAM, UART status line, card_mode fallback, HDMI AXI alive'
}finally{ Pop-Location }
