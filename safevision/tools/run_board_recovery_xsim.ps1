

param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/board_recovery_xsim'),
 [switch]$Waves
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$sv=Join-Path $RepoRoot 'safevision';$run=[IO.Path]::GetFullPath($RunDir)
if($run -match '[^\x00-\x7f]'){throw 'XSim 2018.3 requires ASCII RunDir'}
New-Item -ItemType Directory -Force (Join-Path $run 'tmp')|Out-Null
$oldTmp=$env:TMP;$oldTemp=$env:TEMP
$env:TMP=Join-Path $run 'tmp';$env:TEMP=$env:TMP
try{
 $src=Get-Content -LiteralPath (Join-Path $sv 'tools/run_a_stage11_15_sim.ps1') -Raw
 $rtl=@([regex]::Matches($src,"'((?:platform|rtl)/[^']+\.v)'")|ForEach-Object{$_.Groups[1].Value})
 $rtl+=@('rtl/top/safevision_core/safevision_core.v','rtl/top/safevision_core/bmp_frame_write_bridge.v',
  'rtl/storage/sd_bmp_player.v','rtl/video/hdmi_output/hdmi_video_bridge.v',
    'rtl/video/emergency_graphics/emergency_graphics.v',
    'platform/anlogic_eg4s20_hx4s20c/rtl/board_display_guard.v',
  'platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v',
  'platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v',
  'platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v')
 $rtl+=@('rtl/memory/frame_integrity_guard.v','rtl/memory/video_read_dma_checked.v')
 $rtl=@($rtl|Select-Object -Unique|ForEach-Object{Join-Path $sv $_})
 $sim=@('verification/models/board_memory_contract_model.sv','verification/models/top_ip_stub.sv',
  'verification/unit/tb_safevision_board_recovery.sv')|ForEach-Object{Join-Path $sv $_}
 Copy-Item -LiteralPath (Join-Path $sv 'assets/fonts/font8x16.mem') -Destination $run -Force
 Push-Location -LiteralPath $run
 try{
  Write-XSimProject -Paths $rtl -Path 'rtl.prj'
  & (Join-Path $XSimBin 'xvlog.bat') -d SIM_FAST_TO -i (Join-Path $sv 'rtl/include') --log rtl.log --file 'rtl.prj' > rtl.console.log 2>&1
  if($LASTEXITCODE){throw "RTL compilation failed: $run/rtl.log"}
  Write-XSimProject -Paths $sim -Path 'sim.prj'
  & (Join-Path $XSimBin 'xvlog.bat') --sv -d SIM_FAST_TO -i (Join-Path $sv 'rtl/include') --log tb.log --file 'sim.prj' > tb.console.log 2>&1
  if($LASTEXITCODE){throw "TB compilation failed: $run/tb.log"}
  & (Join-Path $XSimBin 'xelab.bat') work.tb_safevision_board_recovery -s board_recovery -debug typical --timescale 1ns/1ps --log elab.log > elab.console.log 2>&1
  if($LASTEXITCODE){throw "Elaboration failed: $run/elab.log"}
  $tcl=@()
  if($Waves){
   foreach($name in @('card_mode','fb_swap_seen','fb_swap_acked','publish_toggle','publish_slot',
     'publish_gen','frame_ready','submit_valid','submit_ready','slot_sys','gen_sys','crc_sys',
     'axis_ready','axis_valid','axis_user','axis_last','axis_data','hdmi_queue_level',
     'hdmi_resync','hdmi_backpressure','hdmi_dropped_frames','tx_reset','phy_rst_n')){
    $tcl+="log_wave /tb_safevision_board_recovery/dut/$name"
   }
  }
  $tcl+=@('run all','quit');$tcl -join "`n"|Set-Content -LiteralPath run.tcl -Encoding ASCII
  $args=@('board_recovery','-tclbatch','run.tcl','--log','sim.log')
  if($Waves){$args+=@('-wdb','protocol.wdb')}
  & (Join-Path $XSimBin 'xsim.bat') @args > sim.console.log 2>&1
  if($LASTEXITCODE){throw 'Simulator failed'}
  $log=Get-Content -LiteralPath sim.log -Raw
  if($log -notmatch '\[PASS\] BOARD RECOVERY' -or $log -notmatch '\$finish called' -or
     $log -match '(?im)^\s*(\[FAIL\]|FAIL\b|FATAL\b|ERROR:|(?!(?:\[PASS\]))[^\r\n]*\bFAILED\b)'){
   throw "Assertion/finish gate failed: $run/sim.log"
  }
  Write-Output "PASS board recovery: $run/sim.log"
 }finally{Pop-Location}
}finally{$env:TMP=$oldTmp;$env:TEMP=$oldTemp}
