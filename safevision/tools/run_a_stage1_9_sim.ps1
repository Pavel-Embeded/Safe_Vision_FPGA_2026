param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$XSimBin = 'D:\Xilinx\Vivado\2018.3\bin',
    [string]$RunDir = (Join-Path $RepoRoot 'safevision/build/out/a_stage1_9_sim')
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$XSimBin=(Resolve-Path -LiteralPath $XSimBin).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim 2018.3 requires ASCII RunDir'}
$paths=@('rtl/common/a_counter.v','rtl/common/a_debounce.v','rtl/common/a_edge_detect.v','rtl/common/a_mode_fsm.v',
    'rtl/video/pattern_generator/pattern_generator.v','rtl/video/graphics_rom/font8x16_rom.v',
    'rtl/video/osd_overlay/osd_status_text.v','rtl/video/osd_overlay/osd_coordinate_text.v','rtl/video/osd_overlay/osd_overlay.v',
    'rtl/video/osd_overlay/a_graphics_frontend.v','rtl/video/video_pipeline/video_pipeline.v','rtl/video/video_timing/video_timing.v')
$rtl=@($paths | ForEach-Object {Join-Path $RepoRoot "safevision/$_"})
$inc=Join-Path $RepoRoot 'safevision/rtl/include'
$oldTemp=$env:TEMP;$oldTmp=$env:TMP
function Invoke-Case([string]$top,[bool]$mutation=$false){
    $name=if($mutation){'counter_negative_control'}else{$top}
    $caseDir=Join-Path $RunDir $name
    $tempDir=Join-Path $caseDir 'tmp'
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $env:TEMP=$tempDir;$env:TMP=$tempDir
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'safevision/assets/fonts/font8x16.mem') -Destination (Join-Path $caseDir 'font8x16.mem') -Force
    $sources=$rtl.Clone()
    if($mutation){
        $original=Get-Content -LiteralPath $rtl[0] -Raw
        if($original -notmatch 'count == MODULO-1'){throw 'Mutation target missing'}
        $mutant=Join-Path $caseDir 'a_counter_mutant.v'
        [IO.File]::WriteAllText($mutant,$original.Replace('count == MODULO-1','count == ((MODULO == 1000) ? MODULO-2 : MODULO-1)'))
        $sources[0]=$mutant
    }
    Push-Location -LiteralPath $caseDir
    try{
        & (Join-Path $XSimBin 'xvlog.bat') -i $inc --log xvlog.log @sources
        if($LASTEXITCODE -ne 0){throw "$name RTL compile failed"}
        & (Join-Path $XSimBin 'xvlog.bat')  --log xvlog_tb.log (Join-Path $RepoRoot "safevision/verification/unit/$top.v")
        if($LASTEXITCODE -ne 0){throw "$name TB compile failed"}
        & (Join-Path $XSimBin 'xelab.bat') "work.$top" -s "${name}_sim" --timescale '1ns/1ps' --log xelab.log
        if($LASTEXITCODE -ne 0){throw "$name elaborate failed"}
        & (Join-Path $XSimBin 'xsim.bat') "${name}_sim" -runall --log xsim.log
        $result=Get-Content -LiteralPath 'xsim.log' -Raw
        if($mutation){
            if($result -notmatch 'Fatal:.*counter threshold/count/tick' -or $result -match 'PASS tb_a_basics:'){
                throw 'Negative control did not detect the intended counter error'
            }
            Write-Host 'VERIFIED counter negative control: expected assertion failure'
        }elseif($LASTEXITCODE -ne 0 -or $result -notmatch "PASS ${top}:" -or $result -match '(?im)^\s*(FATAL|Fatal:|ERROR|Error:)'){
            throw "$top failed or did not finish"
        }else{Write-Host "VERIFIED $top"}
    }finally{Pop-Location}
}
try{
    foreach($top in @('tb_a_basics','tb_pattern_generator','tb_font8x16_rom','tb_osd_overlay','tb_a_graphics_frontend')){Invoke-Case $top}
    Invoke-Case 'tb_a_basics' $true
    Write-Host 'PASS A stages 1-9 simulation suite (including negative control)'
}finally{$env:TEMP=$oldTemp;$env:TMP=$oldTmp}
