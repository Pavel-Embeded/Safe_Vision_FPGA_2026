# A+B board regression with XSim 2018.3. Generated databases, waves and logs
# belong in RunDir; they are never source artifacts. Memory/HDMI are contracts,
# NOT simulations of the vendor-encrypted SDRAM/HDMI cores or external AC.
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/card_display_xsim'),
 [ValidateSet('adapter','drain','writer','crc','top','card','player','edid','idle','bridge')][string[]]$Case=@('adapter','drain','writer','crc','idle','bridge','edid','top','card'),
 [int]$ReadLatency=4,[switch]$Waves
)
$ErrorActionPreference='Stop'
$sv=Join-Path $RepoRoot 'safevision'
$runRoot=[IO.Path]::GetFullPath($RunDir)
if($runRoot -match '[^\x00-\x7f]'){throw 'XSim 2018.3 requires ASCII RunDir'}
if($ReadLatency -lt 1 -or $ReadLatency -gt 64){throw 'ReadLatency must be 1..64'}
$oldTmp=$env:TMP;$oldTemp=$env:TEMP
try{
 foreach($c in $Case){
  $run=Join-Path $runRoot $c;New-Item -ItemType Directory -Force (Join-Path $run 'tmp')|Out-Null
  $env:TMP=Join-Path $run 'tmp';$env:TEMP=$env:TMP
  if($c -in @('idle','bridge')){
   $rtl=@('rtl/video/hdmi_output/hdmi_video_bridge.v')
   $top=if($c -eq 'idle'){'tb_hdmi_video_bridge_idle'}else{'tb_hdmi_video_bridge'}
   $sim=@("verification/unit/$top.sv")
  }elseif($c -eq 'adapter'){
   $rtl=@('platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v')
   $sim=@('verification/unit/tb_sdram_app_adapter_streaming.sv');$top='tb_sdram_app_adapter_streaming'
  }elseif($c -in @('writer','crc')){
   $rtl=@('rtl/common/crc16_ccitt.v','rtl/memory/frame_address_gen.v','rtl/memory/frame_writer.v')
   $top=if($c -eq 'crc'){'tb_frame_writer_crc_feedback'}else{'tb_frame_writer_full_flag_equivalence'}
   $sim=@("verification/unit/$top.sv")
  }elseif($c -in @('drain','player')){
   $src=Get-Content -LiteralPath (Join-Path $sv 'tools/run_sd_bmp_player_sim.ps1') -Raw
   $rtl=@([regex]::Matches($src,"'((?:platform|rtl)/[^']+\.v)'")|ForEach-Object{$_.Groups[1].Value})
   if($c -eq 'drain'){$sim=@('verification/unit/tb_bmp_frame_sink_drain.sv');$top='tb_bmp_frame_sink_drain'}
   else{$sim=@('verification/models/sd_spi_card_model.sv','verification/unit/tb_sd_bmp_player.sv');$top='tb_sd_bmp_player'}
  }else{
   $src=Get-Content -LiteralPath (Join-Path $sv 'tools/run_a_stage11_15_sim.ps1') -Raw
   $rtl=@([regex]::Matches($src,"'((?:platform|rtl)/[^']+\.v)'")|ForEach-Object{$_.Groups[1].Value})
   $rtl+=@('rtl/top/safevision_core/safevision_core.v','rtl/top/safevision_core/bmp_frame_write_bridge.v',
    'rtl/storage/sd_bmp_player.v','rtl/video/hdmi_output/hdmi_video_bridge.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v')
   $top=if($c -eq 'card'){'tb_safevision_card_display'}elseif($c -eq 'edid'){'tb_safevision_hdmi_reset'}else{'tb_safevision_top'}
   $memory=if($c -eq 'card'){'verification/models/board_memory_contract_model.sv'}else{'verification/models/vendor_ip_stub.sv'}
   $sim=@($memory,'verification/models/top_ip_stub.sv','verification/models/sd_spi_card_model.sv',"verification/unit/$top.sv")
   Copy-Item -LiteralPath (Join-Path $sv 'assets/fonts/font8x16.mem') -Destination $run -Force
  }
  $rtl=@($rtl|Select-Object -Unique|ForEach-Object{Join-Path $sv $_})
  $sim=@($sim|ForEach-Object{Join-Path $sv $_})
  Push-Location -LiteralPath $run
  try{
   & (Join-Path $XSimBin 'xvlog.bat') -d SIM_FAST_TO -i (Join-Path $sv 'rtl/include') --log rtl.log @rtl > rtl.console.log 2>&1
   if($LASTEXITCODE){throw "$c RTL compile failed: $run/rtl.log"}
   & (Join-Path $XSimBin 'xvlog.bat') --sv -d SIM_FAST_TO -i (Join-Path $sv 'rtl/include') --log tb.log @sim > tb.console.log 2>&1
   if($LASTEXITCODE){throw "$c TB compile failed: $run/tb.log"}
   $elab=@("work.$top",'-s','board_test','--timescale','1ns/1ps','--log','elab.log')
   if($Waves -or $c -eq 'card'){$elab+=@('-debug','typical')}
   if($c -eq 'adapter'){$elab+=@('-generic_top',('"RD_LAT={0}"' -f $ReadLatency))}
   & (Join-Path $XSimBin 'xelab.bat') @elab > elab.console.log 2>&1
   if($LASTEXITCODE){throw "$c elaboration failed: $run/elab.log"}
   $tcl=@()
   if($Waves){
    if($c -eq 'crc'){
     foreach($name in @('a','b','c')){
      $tcl+="log_wave /$top/$name/dut/crc_src /$top/$name/dut/crc_src_pend /$top/$name/dut/crc_pair_q /$top/$name/dut/have_lo /$top/$name/dut/wr_pending /$top/$name/rst_n"
     }
    }elseif($c -eq 'edid'){
     foreach($name in @('pixel_rst_n','tx_reset','hdmi_resync','edid_count','edid_trig')){
      $tcl+="log_wave /$top/dut/$name"
     }
    }elseif($c -eq 'idle'){
     $tcl+="log_wave /$top/valid /$top/ready /$top/user /$top/last /$top/data /$top/resync /$top/level"
    }elseif($c -eq 'bridge'){
     foreach($name in @('a','b')){
      $tcl+="log_wave /$top/$name/valid /$top/$name/ready /$top/$name/user /$top/$name/last /$top/$name/data /$top/$name/resync /$top/$name/level"
     }
    }elseif($c -in @('card','top')){
     # Selected protocol/control signals only; no clocks, scan counters, arrays
     # or recursive whole-chip logging. Keep wave size manageable.
     foreach($name in @('app_wr_en','app_rd_en','app_wr_dm','adapter_write_idle','sk_state',
       'sk_frame_done','sk_frame_ok','pl_state','pl_frame_cnt','pl_slot','publish_toggle',
       'publish_slot','frame_ready','swap_state','active','underflows','overflows',
       'frame_fault','hdmi_resync','hdmi_backpressure','hdmi_queue_level','card_mode')){
      $tcl+="log_wave /$top/dut/$name"
     }
    }elseif($c -eq 'adapter'){$tcl+="log_wave /$top/req /$top/wr /$top/ready /$top/aw /$top/ar /$top/wa /$top/ra /$top/dm /$top/rv"}
    elseif($c -eq 'drain'){$tcl+="log_wave /$top/dut/state_o /$top/dut/frame_done /$top/dut/last_frame_ok /$top/dut/swap_toggle"}
    elseif($c -eq 'writer'){$tcl+="log_wave /$top/dut/px_cnt /$top/dut/frame_full /$top/dut/wr_req /$top/dut/wr_done /$top/dut/err_code"}
    else{$tcl+="log_wave /$top/dut_player/state_o /$top/dut_player/frame_active /$top/dut_player/slot_o /$top/dut_player/frame_cnt /$top/dut_player/err_code"}
   }
   if($c -eq 'card'){
    $tcl+='for {set chunk 0} {$chunk < 100} {incr chunk} {'
    $tcl+=' run 20 ms'
    $tcl+=' puts "CARD simulated time: [current_time]"'
    $tcl+=' if {[get_value /tb_safevision_card_display/test_done]} {break}'
    $tcl+='}'
   }else{$tcl+='run all'}
   $tcl+='quit'
   $tcl -join "`n" | Set-Content -LiteralPath run.tcl -Encoding ASCII
   $simArgs=@('board_test','-tclbatch','run.tcl','--log','sim.log')
   if($Waves){$simArgs+=@('-wdb','protocol.wdb')}
   & (Join-Path $XSimBin 'xsim.bat') @simArgs > sim.console.log 2>&1
   if($LASTEXITCODE){throw "$c simulator failed"}
   $log=Get-Content -LiteralPath sim.log -Raw
   if($log -notmatch '(?m)^\s*(\[PASS\]|PASS\b)' -or $log -notmatch '\$finish called' -or
      $log -match '(?im)^\s*(\[FAIL\]|FAIL\b|FATAL\b|ERROR:|(?!(?:\[PASS\]))[^\r\n]*\bFAILED\b)'){
     throw "$c assertion/finish gate failed: $run/sim.log"
   }
   Write-Output "PASS $c : $run/sim.log"
  }finally{Pop-Location}
 }
}finally{$env:TMP=$oldTmp;$env:TEMP=$oldTemp}
