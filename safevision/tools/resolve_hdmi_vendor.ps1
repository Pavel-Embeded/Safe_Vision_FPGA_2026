# Resolve the official HX4S20C HDMI lab source and copy only its HDL dependency
# into an ASCII run directory. No vendor source is fabricated or decrypted.
function Resolve-SafeVisionHdmiVendor {
 param([string]$VendorRoot,[string]$RepoRoot,[string]$RunDir)
 $candidates=@()
 if($VendorRoot){$candidates+=$VendorRoot}
 elseif($env:SAFEVISION_HDMI_VENDOR){$candidates+=$env:SAFEVISION_HDMI_VENDOR}
 else{
  $candidates+=Join-Path $RepoRoot '7_lab_ex_2026_nosoft/example/lab_ex4_tf/src/user_source/hdl_source'
  # Local contest-package installation; other machines pass -VendorRoot.
  $package='D:\嵌赛FPGA文件\HX4S20_Contest_202606.zip\HX4S20_Contest_202606\HX4S20_Contest_202606\7_lab_ex_2026_nosoft'
  if(Test-Path -LiteralPath $package){
   $candidates+=@(Get-ChildItem -LiteralPath $package -Directory | ForEach-Object {Join-Path $_.FullName 'lab_ex4_tf/src/user_source/hdl_source'})
  }
 }
 $selected=$null;$enc=$null
 foreach($p in $candidates){
  $e=Join-Path $p 'hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v'
  if(-not(Test-Path -LiteralPath $e)){$e=Join-Path $p 'hdmi_1_4b_transmitter_core_wrapper.enc.v'}
  if((Test-Path -LiteralPath (Join-Path $p 'hdmi_phy_warpper.v')) -and
     (Test-Path -LiteralPath (Join-Path $p 'lane_lvds_10_1.v')) -and (Test-Path -LiteralPath $e)){
   $selected=(Resolve-Path -LiteralPath $p).Path;$enc=$e;break
  }
 }
 if(-not $selected){throw 'Official HDMI dependency missing. Pass -VendorRoot to the lab_ex4_tf hdl_source directory.'}
 $dest=Join-Path $RunDir 'vendor_hdmi/hdl_source'
 $core=Join-Path $dest 'hdmi1.4b_transmitter_core'
 New-Item -ItemType Directory -Force -Path $core | Out-Null
 foreach($n in @('hdmi_phy_warpper.v','lane_lvds_10_1.v')){
  Copy-Item -LiteralPath (Join-Path $selected $n) -Destination (Join-Path $dest $n) -Force
 }
 Copy-Item -LiteralPath $enc -Destination (Join-Path $core 'hdmi_1_4b_transmitter_core_wrapper.enc.v') -Force
 foreach($n in @('global_def.v','sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v')){
  $f=Join-Path (Split-Path -Parent $enc) $n
  if(Test-Path -LiteralPath $f){Copy-Item -LiteralPath $f -Destination (Join-Path $core $n) -Force}
 }
 $audit=@(Get-ChildItem -LiteralPath $dest -Recurse -File | ForEach-Object {
  [pscustomobject]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()}
 })
 [pscustomobject]@{source=$selected;resolved=[IO.Path]::GetFullPath($dest);files=$audit} |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RunDir 'vendor_hdmi_manifest.json') -Encoding UTF8
 return [IO.Path]::GetFullPath($dest)
}
