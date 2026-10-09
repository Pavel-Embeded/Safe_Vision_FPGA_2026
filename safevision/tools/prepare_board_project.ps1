# Prepare the real HDMI-B GUI entry, retaining the old SDRAM-loopback project.
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$VendorRoot,
 [string]$Python=(Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$project=Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/project'
. (Join-Path $PSScriptRoot 'resolve_hdmi_vendor.ps1')
$resolved=Resolve-SafeVisionHdmiVendor -VendorRoot $VendorRoot -RepoRoot $RepoRoot -RunDir $project
Copy-Item -LiteralPath (Join-Path $RepoRoot 'safevision/assets/fonts/font8x16.mem') -Destination (Join-Path $project 'font8x16.mem') -Force
& $Python (Join-Path $PSScriptRoot 'prepare_board_project.py') --repo $RepoRoot
if($LASTEXITCODE){throw 'GUI preparation failed'}
Write-Output 'BASE GUI entry=safevision.al, HDMI output=B. Build BASE/720p with run_board_sta.ps1 -Mode base,hd.'
