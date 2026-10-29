


param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/storage_integrity_matrix'),
 [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin'
)
$ErrorActionPreference='Stop'
$runner=Join-Path $PSScriptRoot 'run_card_display_xsim.ps1'
$runRoot=[IO.Path]::GetFullPath($RunDir)
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$completed=@()
function Invoke-Member([string]$name,[hashtable]$arguments){
 $arguments.RepoRoot=$RepoRoot
 $arguments.RunDir=Join-Path $runRoot $name
 $arguments.XSimBin=$XSimBin
 & $runner @arguments *> (Join-Path $runRoot ($name+'.console.log'))
 if(-not $?){throw "Matrix member failed: $name"}
 $script:completed+=$name
 Write-Output "PASS matrix member $name"
}
foreach($latency in @(1,4,7,16,32,64)){
 foreach($fast in @(0,1)){
  Invoke-Member "adapter_lat${latency}_fast${fast}" @{Case='adapter';ReadLatency=$latency;FastRead=$fast}
 }
}
foreach($latency in @(1,4,7,11,16,32,64)){
 Invoke-Member "adapter_prefetch_lat${latency}" @{Case='adapter';ReadLatency=$latency;FastRead=1;PrefetchRead=1}
}
foreach($shape in @(@(0,0,0),@(1,0,1),@(1,7,3),@(0,32,8))){
 $ack=$shape[0];$gap=$shape[1];$source=$shape[2]
 Invoke-Member "integrity_ack${ack}_gap${gap}_source${source}" @{Case='integrity';AckFirst=$ack;ResponseGap=$gap;SourceGap=$source;HeaderLate=1}
}


Invoke-Member 'memory_base_lat1' @{Case='memory';HD=0;ReadLatency=1;WriteLoad=0}
$manifest=[ordered]@{complete=$true;members=$completed;member_count=$completed.Count;
 hardware_verified=$false;encrypted_vendor_behavior_verified=$false}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'matrix.json') -Encoding UTF8
Write-Output "PASS storage integrity matrix: $($completed.Count) members"
