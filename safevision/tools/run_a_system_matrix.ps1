
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$ModelSimBin=$env:MSIM_BIN,
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/a_system_matrix'),
 [ValidateSet('Auto','XSim','ModelSim')][string]$Tool='Auto',
 [switch]$Waves
)
$ErrorActionPreference='Stop'
foreach($h in @(0,1)){
 foreach($policy in @(0,1)){
  $argsForCase=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'run_a_system_sim.ps1'),
   '-RepoRoot',$RepoRoot,'-RunDir',$RunDir,'-Tool',$Tool,'-HD',$h,'-Immediate',$policy,
   '-XSimBin',$XSimBin)
  if($ModelSimBin){$argsForCase+=@('-ModelSimBin',$ModelSimBin)}
  if($Waves){$argsForCase+='-Waves'}
  & powershell @argsForCase
  if($LASTEXITCODE){throw "A system matrix failed HD=$h policy=$policy"}
 }
}
Write-Output 'PASS complete A system matrix: BASE/HD x immediate/frame-boundary'
