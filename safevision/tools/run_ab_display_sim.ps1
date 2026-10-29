

param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/ab_display'),
 [ValidateSet('Auto','XSim','ModelSim')][string]$Tool='Auto',
 [switch]$Waves
)
$ErrorActionPreference='Stop'
$p=@{RepoRoot=$RepoRoot;ModelSimBin=$ModelSimBin;XSimBin=$XSimBin;
 RunDir=$RunDir;Tool=$Tool;Waves=$Waves}

& (Join-Path $PSScriptRoot 'run_ab_integration.ps1') @p -Top tb_ab_frame_display
& (Join-Path $PSScriptRoot 'run_ab_integration.ps1') @p -Top tb_safevision_core -SwapCount 4
& (Join-Path $PSScriptRoot 'run_ab_integration.ps1') @p -Top tb_safevision_core -HD 1 -SwapCount 4
& (Join-Path $PSScriptRoot 'run_ab_integration.ps1') @p -Top tb_safevision_core -SubmitLead 1
Write-Output 'PASS AB display suite: direct chain, production BASE, HD, boundary'
