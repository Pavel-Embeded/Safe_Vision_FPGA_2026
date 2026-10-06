# ============================================================================
# run_sim.ps1 - SafeVision B-chain regression (ModelSim)
# ----------------------------------------------------------------------------
# Layout follows the "blueprint" repo tree:
#     rtl/include/      shared defs (safevision_defs.vh, fault_code_defs.vh)
#     rtl/common/       platform-independent helpers (CDC / FIFO / UART / skid)
#     rtl/storage/      SPI / SD / FAT32 / file stream / file index
#     rtl/media/        RAW / BMP / WAV parsers
#     rtl/memory/       SDRAM wrapper / frame buffer / arbiter / frame swap / DMA
#     verification/     unit testbenches + models   (work/ is created here)
#     tools/            this script
#
# Usage (PowerShell):
#     powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_sim.ps1
#     powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_sim.ps1 -ModelSimBin D:\path\to\win64
#   The ModelSim win64 directory comes from -ModelSimBin, or from the MSIM_BIN
#   environment variable when the parameter is omitted. Same convention as
#   run_clock_sim.ps1. No machine-specific path is hard-coded here.
#
# NOTE 1: keep this file ASCII-only. PowerShell 5.1 reads .ps1 as ANSI when there
#         is no BOM, so multi-byte (Chinese) comments can swallow following quote
#         characters and break parsing. Chinese comments live in the RTL files.
# NOTE 2: +define+SIM_FAST_TO scales the SD timeouts down so that the timeout
#         exit branches can actually be reached in acceptable sim time.
#         Those scaled values are SIMULATION ONLY - the product values in
#         safevision_defs.vh must be re-measured on the real board.
# NOTE 3: output is a transient console transcript; do not store it under
#         evidence/ or commit it. Record only concise results in Markdown.
# ============================================================================

# ModelSim install path: -ModelSimBin, or MSIM_BIN env var. No baked-in default.
param([string]$ModelSimBin = $env:MSIM_BIN)

if ([string]::IsNullOrWhiteSpace($ModelSimBin)) {
    [Console]::Error.WriteLine('Set MSIM_BIN or pass -ModelSimBin with the ModelSim win64 directory.')
    exit 2
}
$env:PATH += ";$ModelSimBin"

$SV = Split-Path $PSScriptRoot -Parent
Set-Location (Join-Path $SV "verification")

$INC = "+incdir+../rtl/include"
$DEF = "+define+SIM_FAST_TO"

$RTL = @(
    # ---- common ----
    "../rtl/common/uart_tx.v",
    "../rtl/common/rv_skid_buffer.v",
    "../rtl/common/sync_fifo.v",
    "../rtl/memory/fifo_health_monitor.v",
    "../rtl/common/error_report.v",
    "../rtl/common/shift_reg.v",
    "../rtl/common/spi_byte_rx.v",
    "../rtl/common/crc16_ccitt.v",
    "../rtl/common/crc7.v",
    # ---- storage ----
    "../rtl/storage/spi_master.v",
    "../rtl/storage/sd_initializer.v",
    "../rtl/storage/sd_sector_reader.v",
    "../rtl/storage/mbr_parser.v",
    "../rtl/storage/fat32_boot_parser.v",
    "../rtl/storage/fat32_directory_scanner.v",
    "../rtl/storage/fat32_cluster_walker.v",
    "../rtl/storage/file_streamer.v",
    "../rtl/storage/file_index.v",
    # ---- media ----
    "../rtl/media/bmp_parser.v",
    "../rtl/media/bmp_unpack.v",
    "../rtl/media/wav_parser.v",
    # ---- memory ----
    "../rtl/memory/mem_ctrl.v",
    "../rtl/memory/mem_read_burst.v",
    "../rtl/memory/frame_address_gen.v",
    "../rtl/memory/frame_writer.v",
    "../rtl/top/safevision_core/bmp_frame_write_bridge.v",
    "../rtl/memory/frame_buffer_manager.v",
    "../rtl/memory/memory_arbiter.v",
    "../rtl/memory/video_read_dma.v",
    "../rtl/memory/frame_swap_ctrl.v",
    "../rtl/memory/frame_swap_cdc.v",
    "../rtl/memory/memory_bandwidth_monitor.v",
    "../rtl/memory/framebuffer_loopback_core.v",
    "../rtl/memory/sdr_pat_gen.v",
    # ---- platform bring-up top (touches pins, so it lives under platform/) ----
    "../platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v",
    # ---- board bring-up top that instantiates the vendor IP; pulled into the
    #      regression by binding sdram / sv_system_pll to the stubs in models/ ----
    "../platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v",
    # ---- board adapter (no encrypted IP inside; compile-checked + unit TB) ----
    "../platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v",
    # ---- Plan A sink: official a_pixel_fifo (wr 50 MHz / rd 125 MHz) + the
    #      mem-side frame controller. Covered by tb_bmp_frame_sink below. ----
    "../platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_ip.v",
    "../platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_eram.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/a_pixel_fifo.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v"
)

$SIM = @(
    "models/sd_spi_card_model.sv",
    "models/frame_memory_model.sv",
    "models/vendor_ip_stub.sv",
    "unit/tb_sd_sector_reader.sv",
    "unit/tb_mbr_parser.sv",
    "unit/tb_sd_initializer.sv",
    "unit/tb_fat32_boot_parser.sv",
    "unit/tb_fat32_directory_scanner.sv",
    "unit/tb_fat32_cluster_walker.sv",
    "unit/tb_file_streamer.sv",
    "unit/tb_bmp_parser.sv",
    "unit/tb_file_index.sv",
    "unit/tb_common_fifo.sv",
    "unit/tb_crc.sv",
    "unit/tb_bmp_unpack.sv",
    "unit/tb_wav_parser.sv",
    "unit/tb_frame_writer.sv",
    "unit/tb_memory_arbiter.sv",
    "unit/tb_frame_swap_ctrl.sv",
    "unit/tb_top_stage5_sector_rd.sv",
    "unit/tb_top_stage6_fat32_mount.sv",
    "unit/tb_framebuffer_loopback_core.sv",
    "unit/tb_sdram_app_adapter.sv",
    "unit/tb_sdr_pat_gen.sv",
    "unit/tb_top_sdram_loopback.sv",
    "unit/tb_ab_storage_contract.sv",
    "unit/tb_b_frame_memory.sv",
    "unit/tb_bmp_frame_write_bridge.sv",
    "unit/tb_frame_writer_bounds.sv",
    "unit/tb_sd_clock_params.sv",
    "unit/tb_bmp_frame_sink.sv"
)

$TBS = @(
    "tb_sd_sector_reader",
    "tb_mbr_parser",
    "tb_sd_initializer",
    "tb_fat32_boot_parser",
    "tb_fat32_directory_scanner",
    "tb_fat32_cluster_walker",
    "tb_file_streamer",
    "tb_bmp_parser",
    "tb_file_index",
    "tb_common_fifo",
    "tb_crc",
    "tb_bmp_unpack",
    "tb_wav_parser",
    "tb_frame_writer",
    "tb_memory_arbiter",
    "tb_frame_swap_ctrl",
    "tb_top_stage5_sector_rd",
    "tb_top_stage6_fat32_mount",
    "tb_framebuffer_loopback_core",
    "tb_sdram_app_adapter",
    "tb_sdr_pat_gen",
    "tb_top_sdram_loopback",
    "tb_ab_storage_contract",
    "tb_b_frame_memory",
    "tb_bmp_frame_write_bridge",
    "tb_frame_writer_bounds",
    "tb_sd_clock_params",
    "tb_bmp_frame_sink"
)

Write-Output "=== vlib work ==="
vlib work

Write-Output "=== vlog ($DEF) ==="
vlog $DEF $INC $RTL $SIM
if ($LASTEXITCODE -ne 0) {
    Write-Output "COMPILE FAILED"
    exit 1
}

$total_pass = 0
$total_fail = 0
foreach ($tb in $TBS) {
    Write-Output ""
    Write-Output "=== vsim $tb ==="
    $out = vsim -c -do "run -all; quit -f" $tb 2>&1 | Out-String
    $p = ([regex]::Matches($out, "\[PASS\]")).Count
    $f = ([regex]::Matches($out, "\[FAIL\]")).Count
    $total_pass += $p
    $total_fail += $f
    Write-Output ("  -> PASS=$p FAIL=$f")
    if ($f -ne 0) {
        ($out -split "`n") | Select-String -Pattern "\[FAIL\]"
    }
}

Write-Output ""
Write-Output "============================================"
Write-Output ("  TOTAL PASS=$total_pass FAIL=$total_fail")
Write-Output "============================================"
if ($total_fail -ne 0) { exit 1 }