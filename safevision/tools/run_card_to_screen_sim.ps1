


param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/card_to_display'),
 [ValidateSet('Auto','XSim','ModelSim')][string]$Tool='Auto',
 [switch]$Waves
)
$ErrorActionPreference='Stop'
$p=@{RepoRoot=$RepoRoot;ModelSimBin=$ModelSimBin;XSimBin=$XSimBin;
 RunDir=$RunDir;Tool=$Tool;Waves=$Waves}

& (Join-Path $PSScriptRoot 'run_ab_integration.ps1') @p -Top tb_card_to_display
Write-Output 'PASS complete card-to-display suite'
