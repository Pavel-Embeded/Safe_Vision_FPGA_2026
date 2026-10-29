

param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/a_stage11_15_sim'),
 [string[]]$Top=@('tb_a_pixel_fifo','tb_video_stream_cdc','tb_frame_slot_commit',
 'tb_frame_reader','tb_osd_text_layer','tb_video_compositor','tb_a_video_display_core',
 'tb_a_video_display_core_stress','tb_pixel_word_packer_stress')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim2018.3 requires an ASCII RunDir'}
$files=@(

 'platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_ip.v',
 'platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_eram.v',
 'platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/a_pixel_fifo.v',
 'rtl/video/frame_reader/pixel_word_packer.v',
 'rtl/video/video_pipeline/video_stream_slice.v',
 'rtl/video/video_cdc/video_level_sync.v',
 'rtl/video/video_cdc/video_cdc_mailbox.v',
 'rtl/common/rv_skid_buffer.v',
 'rtl/memory/video_read_dma.v',
 'rtl/memory/memory_arbiter.v',
 'rtl/memory/frame_swap_cdc.v',
 'rtl/memory/frame_swap_ctrl.v',
 'rtl/video/frame_reader/frame_slot_commit.v',
 'rtl/video/frame_reader/frame_reader.v',
 'rtl/video/frame_reader/a_frame_fetch_bridge.v',
 'rtl/video/video_pipeline/a_video_display_core.v',
 'rtl/video/video_compositor/video_layer_delay.v',
 'rtl/video/video_compositor/video_compositor.v',
 'rtl/video/osd_overlay/osd_text_layer.v',
 'rtl/video/osd_overlay/osd_status_text.v',
 'rtl/video/graphics_rom/font8x16_rom.v',
 'rtl/video/video_pipeline/video_pipeline.v',
 'rtl/video/video_timing/video_timing.v',
 'platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v',
 'rtl/common/uart_tx.v',
 'rtl/common/sync_fifo.v',
 'rtl/memory/fifo_health_monitor.v',
 'rtl/common/error_report.v',
 'rtl/common/shift_reg.v',
 'rtl/common/spi_byte_rx.v',
 'rtl/common/crc16_ccitt.v',
 'rtl/common/crc7.v',
 'rtl/storage/spi_master.v',
 'rtl/storage/sd_initializer.v',
 'rtl/storage/sd_sector_reader.v',
 'rtl/storage/mbr_parser.v',
 'rtl/storage/fat32_boot_parser.v',
 'rtl/storage/fat32_directory_scanner.v',
 'rtl/storage/fat32_cluster_walker.v',
 'rtl/storage/file_streamer.v',
 'rtl/storage/file_index.v',
 'rtl/media/bmp_parser.v',
 'rtl/media/bmp_unpack.v',
 'rtl/media/wav_parser.v',
 'rtl/memory/mem_ctrl.v',
 'rtl/memory/mem_read_burst.v',
 'rtl/memory/frame_address_gen.v',
 'rtl/memory/frame_writer.v',
 'rtl/memory/frame_buffer_manager.v',
 'rtl/memory/memory_bandwidth_monitor.v',
 'rtl/memory/framebuffer_loopback_core.v',
 'rtl/memory/sdr_pat_gen.v',
 'platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v',
 'platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v',
 'platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v',
 'platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v',
 'rtl/common/a_counter.v',
 'rtl/common/a_debounce.v',
 'rtl/common/a_edge_detect.v',
 'rtl/common/a_mode_fsm.v',
 'rtl/video/pattern_generator/pattern_generator.v',
 'rtl/video/osd_overlay/osd_coordinate_text.v',
 'rtl/video/osd_overlay/osd_overlay.v',
 'rtl/video/osd_overlay/a_graphics_frontend.v'
) | ForEach-Object {Join-Path $RepoRoot "safevision/$_"}
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
try {
 foreach($case in $Top){
  if($case -notin @('tb_a_pixel_fifo','tb_video_stream_cdc','tb_frame_slot_commit',
    'tb_frame_reader','tb_osd_text_layer','tb_video_compositor','tb_a_video_display_core',
 'tb_a_video_display_core_stress','tb_pixel_word_packer_stress')){throw 'Unknown test top'}
  $dir=Join-Path $RunDir $case
  New-Item -ItemType Directory -Force -Path (Join-Path $dir 'tmp') | Out-Null
  $env:TEMP=Join-Path $dir 'tmp';$env:TMP=$env:TEMP
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'safevision/assets/fonts/font8x16.mem') -Destination (Join-Path $dir 'font8x16.mem') -Force
  Push-Location -LiteralPath $dir
  try {
   Write-XSimProject -Paths $files -Path 'files.prj'
   & (Join-Path $XSimBin 'xvlog.bat') -i (Join-Path $RepoRoot 'safevision/rtl/include') --file 'files.prj' --log rtl.log > rtl.console.log 2>&1
   if($LASTEXITCODE){throw 'Combined A+B RTL compile failed'}
   & (Join-Path $XSimBin 'xvlog.bat')  -i (Join-Path $RepoRoot 'safevision/rtl/include') (Join-Path $RepoRoot "safevision/verification/unit/$case.v") --log tb.log > tb.console.log 2>&1
   if($LASTEXITCODE){throw 'TB compile failed'}
   & (Join-Path $XSimBin 'xelab.bat') "work.$case" -s $case --timescale '1ns/1ps' --log elab.log > elab.console.log 2>&1
   if($LASTEXITCODE){throw 'Elaboration failed'}
   & (Join-Path $XSimBin 'xsim.bat') $case -runall --log sim.log > sim.console.log 2>&1
   $code=$LASTEXITCODE;$log=Get-Content -LiteralPath 'sim.log' -Raw
   if($code -ne 0 -or $log -notmatch "PASS ${case}:" -or $log -match '(?im)^\s*(Fatal:|FATAL|ERROR:)'){throw "Simulation failed: $dir"}
   $log -split "`n" | Where-Object {$_ -match "PASS ${case}:|reader W=|display HD=|compositor N/O/E="}
  }finally{Pop-Location}
 }
 Write-Output "PASS A stages11-15 suite: $($Top.Count) selected tests"
}finally{$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
