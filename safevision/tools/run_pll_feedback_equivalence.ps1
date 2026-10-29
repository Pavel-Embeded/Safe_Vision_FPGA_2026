
param(
    [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$BeforeRef='021e4150d618cca5468309a208438ab701221de5',
    [string]$GitExe='git',
    [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
    [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/pll_feedback_equivalence')
)
$ErrorActionPreference='Stop'
$RepoRoot=[IO.Path]::GetFullPath($RepoRoot)
$RunDir=[IO.Path]::GetFullPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim 2018.3 needs ASCII RunDir'}
$relative='safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll'
$names=@('sv_system_pll','sv_video_vga_pll','sv_video_hd_pll','sv_audio_pll')
$before=Join-Path $RunDir 'before'
New-Item -ItemType Directory -Force -Path $before | Out-Null
$old=@();$current=@()
$utf8=New-Object Text.UTF8Encoding($false)
foreach($name in $names){
    $oldText=(& $GitExe -C $RepoRoot show "${BeforeRef}:${relative}/${name}.v") -join "`n"
    if($LASTEXITCODE -ne 0){throw "Cannot read baseline $BeforeRef; use a clone containing this commit"}
    $newPath=Join-Path $RepoRoot "$relative/$name.v"
    $newText=[IO.File]::ReadAllText($newPath)
    $pattern='(?s)EG_PHY_PLL #\((.*?)\) pll_inst'
    $oldParams=[regex]::Match($oldText,$pattern)
    $newParams=[regex]::Match($newText,$pattern)
    if(-not $oldParams.Success -or -not $newParams.Success -or
        $oldParams.Groups[1].Value.Trim() -cne $newParams.Groups[1].Value.Replace("`r",'').Trim()){
        throw "PLL hardware parameters changed: $name"
    }
    $module="module $name ("
    if(-not $oldText.Contains($module)){throw "Baseline module missing: $name"}
    $oldPath=Join-Path $before "${name}_before.v"
    [IO.File]::WriteAllText($oldPath,$oldText.Replace($module,"module ${name}_before ("),$utf8)
    $old+=$oldPath;$current+=$newPath
}
$model=@((Join-Path $TdRoot 'sim_release/eg4/eg_logic_clk.v'),(Join-Path $TdRoot 'sim_release/eg4/eg_phy_pll.v'))
$tb=Join-Path $RepoRoot 'safevision/verification/unit/tb_pll_feedback_equivalence.v'
$savedTemp=$env:TEMP;$savedTmp=$env:TMP
try{
    foreach($case in @('equivalence','phase_negative_control')){
        $caseDir=Join-Path $RunDir $case
        $temp=Join-Path $caseDir 'tmp'
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $env:TEMP=$temp;$env:TMP=$temp
        $candidate=$current.Clone()
        if($case -eq 'phase_negative_control'){
            $mutant=Join-Path $caseDir 'system_phase_mutant.v'
            $text=[IO.File]::ReadAllText($current[0])
            if(-not $text.Contains('.CLKC2_CPHASE(3)')){throw 'Negative-control phase target missing'}
            [IO.File]::WriteAllText($mutant,$text.Replace('.CLKC2_CPHASE(3)','.CLKC2_CPHASE(2)'),$utf8)
            $candidate[0]=$mutant
        }
        Push-Location -LiteralPath $caseDir
        try{
            & (Join-Path $XSimBin 'xvlog.bat') --log xvlog.log @model @old @candidate
            if($LASTEXITCODE -ne 0){throw "$case RTL compile failed"}
            & (Join-Path $XSimBin 'xvlog.bat')  --log xvlog_tb.log $tb
            if($LASTEXITCODE -ne 0){throw "$case TB compile failed"}
            & (Join-Path $XSimBin 'xelab.bat') work.tb_pll_feedback_equivalence -s pll_equivalence_sim --timescale '1ns/1ps' --log xelab.log
            if($LASTEXITCODE -ne 0){throw "$case elaboration failed"}
            & (Join-Path $XSimBin 'xsim.bat') pll_equivalence_sim -runall --log xsim.log
            $simExit=$LASTEXITCODE
            $log=[IO.File]::ReadAllText((Join-Path $caseDir 'xsim.log'))
            if($case -eq 'equivalence'){
                if($simExit -ne 0 -or $log -match '(?im)^\s*(Fatal:|FATAL|ERROR:)' -or
                    -not $log.Contains('PASS tb_pll_feedback_equivalence:')){throw 'PLL equivalence failed'}
            }else{
                if($log.Contains('PASS tb_pll_feedback_equivalence:') -or
                    $log -notmatch 'PLL edge equivalence id=2|System PLL memory phase no longer 180 degrees'){
                    throw 'Negative control did not detect the intended memory-phase fault'
                }
            }
            Write-Output "PASS $case"
        }finally{Pop-Location}
    }
}finally{$env:TEMP=$savedTemp;$env:TMP=$savedTmp}
Write-Output 'PASS PLL parameter identity, functional equivalence and phase negative control'
