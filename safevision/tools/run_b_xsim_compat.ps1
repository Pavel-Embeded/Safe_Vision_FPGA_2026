

param(
    [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
    [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/b_xsim_compat')
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'xsim_project.ps1')
$repo=[IO.Path]::GetFullPath($RepoRoot)
$runDir=[IO.Path]::GetFullPath($RunDir)
if($runDir -match '[^\x00-\x7f]'){throw 'XSim 2018.3 needs an ASCII RunDir.'}
$xsimBin=$XSimBin
$original=Get-Content -LiteralPath (Join-Path $repo 'safevision/tools/run_sim.ps1') -Raw
function Get-OriginalPaths($name) {
    $match=[regex]::Match($original, ('(?s)\$'+$name+' = @\((.*?)\n\)'))
    if(-not $match.Success){throw "Cannot find original $name source list"}
    @([regex]::Matches($match.Groups[1].Value,'"([^"]+)"') | ForEach-Object {
        [IO.Path]::GetFullPath((Join-Path (Join-Path $repo 'safevision/verification') $_.Groups[1].Value))
    })
}
$rtl=Get-OriginalPaths 'RTL'
$tb=Get-OriginalPaths 'SIM'
$rtl+=Join-Path $repo 'safevision/rtl/video/video_pipeline/video_pipeline.v'
$rtl+=Join-Path $repo 'safevision/rtl/video/video_timing/video_timing.v'
$aSources=@('common/a_counter.v','common/a_debounce.v','common/a_edge_detect.v','common/a_mode_fsm.v',
    'video/pattern_generator/pattern_generator.v','video/graphics_rom/font8x16_rom.v',
    'video/osd_overlay/osd_status_text.v','video/osd_overlay/osd_coordinate_text.v',
    'video/osd_overlay/osd_overlay.v','video/osd_overlay/a_graphics_frontend.v')
foreach($source in $aSources){$rtl+=Join-Path $repo "safevision/rtl/$source"}

$topMatch=[regex]::Match($original,'(?s)\$TBS = @\((.*?)\n\)')
if(-not $topMatch.Success){throw 'Cannot find current B top list'}
$tops=@([regex]::Matches($topMatch.Groups[1].Value,'"(tb_[^"]+)"') | ForEach-Object {$_.Groups[1].Value})
if($tops.Count -eq 0){throw 'Empty B regression selection'}
New-Item -ItemType Directory -Force -Path (Join-Path $runDir 'tmp') | Out-Null
$previousTemp=$env:TEMP;$previousTmp=$env:TMP
$failures=@()
$assertions=0
Push-Location -LiteralPath $runDir
try {
    $env:TEMP=Join-Path $runDir 'tmp';$env:TMP=$env:TEMP
    Write-XSimProject -Paths $rtl -Path 'rtl.prj'
    & (Join-Path $xsimBin 'xvlog.bat') -d SIM_FAST_TO -i (Join-Path $repo 'safevision/rtl/include') --log all_rtl.log --file 'rtl.prj'
    if($LASTEXITCODE -ne 0){throw 'B+A combined Verilog compile failed'}
    Write-XSimProject -Paths $tb -Path 'tb.prj'
    & (Join-Path $xsimBin 'xvlog.bat') --sv -d SIM_FAST_TO -i (Join-Path $repo 'safevision/rtl/include') --log all_tb.log --file 'tb.prj'
    if($LASTEXITCODE -ne 0){throw 'B TB compile failed'}
    foreach($top in $tops){
        & (Join-Path $xsimBin 'xelab.bat') "work.$top" -s "${top}_sim" --timescale '1ns/1ps' --log "${top}_elab.log"
        if($LASTEXITCODE -ne 0){throw "$top elaboration failed"}
        & (Join-Path $xsimBin 'xsim.bat') "${top}_sim" -runall --log "${top}_sim.log"
        if($LASTEXITCODE -ne 0){throw "$top simulation failed"}
        $log=[IO.File]::ReadAllText((Join-Path $runDir "${top}_sim.log"),[Text.Encoding]::UTF8)
        if($log -notmatch '\[PASS\]' -or $log -notmatch '\$finish called' -or $log -match '(?im)(\[FAIL\]|\[SKIP\]|^\s*(FAIL\b|FATAL\b|Fatal:|ERROR:|\[RESULT\].*FAILED))'){
            $failures+=$top
            Write-Host "FAILED EXISTING $top"
            continue
        }
        $assertions+=([regex]::Matches($log,'\[PASS\]')).Count
        Write-Host "VERIFIED EXISTING $top"
    }
    if($failures.Count){throw "Existing XSim failures: $($failures -join ', ')"}
    Write-Host "B+A COMPILE AND B FUNCTIONAL PASS: tests=$($tops.Count) checks=$assertions"
}finally{Pop-Location;$env:TEMP=$previousTemp;$env:TMP=$previousTmp}
