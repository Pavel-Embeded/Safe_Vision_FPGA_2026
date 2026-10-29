param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$XSimBin = 'D:\Xilinx\Vivado\2018.3\bin',
    [string]$RunDir = (Join-Path $RepoRoot 'safevision/build/out/video_pipeline_sim')
)


$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$XSimBin = (Resolve-Path -LiteralPath $XSimBin).Path
$RunDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
if ($RunDir -match '[^\x00-\x7f]') { throw 'XSim 2018.3 needs an ASCII RunDir.' }
$rtl = @(
    (Join-Path $RepoRoot 'safevision/rtl/video/video_pipeline/video_pipeline.v'),
    (Join-Path $RepoRoot 'safevision/rtl/video/video_timing/video_timing.v')
)
$inc = Join-Path $RepoRoot 'safevision/rtl/include'
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
try {
    foreach ($top in @('tb_video_pipeline','tb_video_pipeline_timing')) {
        $caseDir = Join-Path $RunDir $top
        $tempDir = Join-Path $caseDir 'tmp'
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $env:TEMP = $tempDir
        $env:TMP = $tempDir
        Push-Location -LiteralPath $caseDir
        try {
            & (Join-Path $XSimBin 'xvlog.bat') -i $inc --log xvlog.log @rtl
            if ($LASTEXITCODE -ne 0) { throw "$top RTL compile failed" }
            & (Join-Path $XSimBin 'xvlog.bat') --sv --log xvlog_tb.log (Join-Path $RepoRoot "safevision/verification/unit/$top.sv")
            if ($LASTEXITCODE -ne 0) { throw "$top TB compile failed" }
            & (Join-Path $XSimBin 'xelab.bat') "work.$top" -s "${top}_sim" --timescale '1ns/1ps' --log xelab.log
            if ($LASTEXITCODE -ne 0) { throw "$top elaboration failed" }
            & (Join-Path $XSimBin 'xsim.bat') "${top}_sim" -runall --log xsim.log
            if ($LASTEXITCODE -ne 0) { throw "$top simulation failed" }
            $result = Get-Content -LiteralPath 'xsim.log' -Raw
            if ($result -notmatch "PASS ${top}:" -or $result -match '(?im)^\s*(FATAL|Fatal:|ERROR|Error:)') {
                throw "$top failed or did not finish"
            }
            Write-Host "VERIFIED $top"
        } finally { Pop-Location }
    }
} finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
}
