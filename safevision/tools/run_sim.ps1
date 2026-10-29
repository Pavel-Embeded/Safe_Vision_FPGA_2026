                                                                              
                                                        
                                                                              
                                           
                                                                            
                                                                               
                                                                   
                                               
                                                                                 
                                                                           
                                   
 
                     
                                                                             
                                                                                                           
                                                                              
                                                                          
                                                                   
 
                                                                                 
                                                                                 
                                                                               
                                                                             
                                                                       
                                                                         
                                                                   
                                                                         
                                                                          
                                                                              

                                                                                
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
                      
    "../rtl/common/uart_tx.v",
    "../rtl/common/rv_skid_buffer.v",
    "../rtl/common/sync_fifo.v",
    "../rtl/memory/fifo_health_monitor.v",
    "../rtl/common/error_report.v",
    "../rtl/common/shift_reg.v",
    "../rtl/common/spi_byte_rx.v",
    "../rtl/common/crc16_ccitt.v",
    "../rtl/common/crc7.v",
                       
    "../rtl/storage/spi_master.v",
    "../rtl/storage/sd_initializer.v",
    "../rtl/storage/sd_sector_reader.v",
    "../rtl/storage/mbr_parser.v",
    "../rtl/storage/fat32_boot_parser.v",
    "../rtl/storage/fat32_directory_scanner.v",
    "../rtl/storage/fat32_cluster_walker.v",
    "../rtl/storage/file_streamer.v",
    "../rtl/storage/file_index.v",
                     
    "../rtl/media/bmp_parser.v",
    "../rtl/media/bmp_unpack.v",
    "../rtl/media/wav_parser.v",
                      
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
                                                                                 
    "../platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v",
                                                                              
                                                                                   
    "../platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v",
                                                                                 
    "../platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v",
                                                                            
                                                                              
    "../platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_ip.v",
    "../platform/anlogic_eg4s20_hx4s20c/ip/a_pixel_fifo/a_pixel_fifo_eram.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/a_pixel_fifo.v",
    "../platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v"
)

$SIM = @(
    "models/sd_spi_card_model.v",
    "models/frame_memory_model.v",
    "models/vendor_ip_stub.v",
    "unit/tb_sd_sector_reader.v",
    "unit/tb_mbr_parser.v",
    "unit/tb_sd_initializer.v",
    "unit/tb_fat32_boot_parser.v",
    "unit/tb_fat32_directory_scanner.v",
    "unit/tb_fat32_cluster_walker.v",
    "unit/tb_file_streamer.v",
    "unit/tb_bmp_parser.v",
    "unit/tb_file_index.v",
    "unit/tb_common_fifo.v",
    "unit/tb_crc.v",
    "unit/tb_bmp_unpack.v",
    "unit/tb_wav_parser.v",
    "unit/tb_frame_writer.v",
    "unit/tb_memory_arbiter.v",
    "unit/tb_frame_swap_ctrl.v",
    "unit/tb_top_stage5_sector_rd.v",
    "unit/tb_top_stage6_fat32_mount.v",
    "unit/tb_framebuffer_loopback_core.v",
    "unit/tb_sdram_app_adapter.v",
    "unit/tb_sdr_pat_gen.v",
    "unit/tb_top_sdram_loopback.v",
    "unit/tb_ab_storage_contract.v",
    "unit/tb_b_frame_memory.v",
    "unit/tb_bmp_frame_write_bridge.v",
    "unit/tb_frame_writer_bounds.v",
    "unit/tb_sd_clock_params.v",
    "unit/tb_bmp_frame_sink.v"
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