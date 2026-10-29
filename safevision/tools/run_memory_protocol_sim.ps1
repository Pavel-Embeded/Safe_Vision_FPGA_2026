
param(
    [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$XSimBin='D:\Xilinx\Vivado\2018.3\bin',
    [string]$GitExe='git',
    [string]$RunDir=(Join-Path $RepoRoot 'safevision/build/out/memory_protocol_sim'),
    [switch]$SkipNegativeControls
)
$ErrorActionPreference='Stop'
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$RunDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RunDir)
if($RunDir -match '[^\x00-\x7f]'){throw 'XSim 2018.3 needs an ASCII RunDir'}
$rtlNames=@('memory_arbiter','video_read_dma','frame_swap_ctrl','frame_swap_cdc')
$tops=@('tb_memory_arbiter_backpressure','tb_memory_arbiter_read_latency','tb_video_read_dma_burst64',
        'tb_frame_swap_vblank_ack','tb_frame_swap_default_timeout','tb_memory_arbiter_protocol','tb_video_read_dma_integration')
$oldFailures=@{
    tb_memory_arbiter_backpressure='ARB_ONE_WORD_BACKPRESSURE';
    tb_memory_arbiter_read_latency='ARB_DELAYED_RESPONSE_LOST';
    tb_video_read_dma_burst64='DMA_BURST64_HANG';
    tb_frame_swap_vblank_ack='SWAP_EARLY_ACK_LOST';
    tb_frame_swap_default_timeout='SWAP_DEFAULT_TIMEOUT_BEFORE_VBLANK'
}
$previousTemp=$env:TEMP;$previousTmp=$env:TMP
try {
    foreach($variant in @('corrected','old_code_negative_controls')) {
        if($variant -ne 'corrected' -and $SkipNegativeControls){continue}
        $dir=Join-Path $RunDir $variant
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'tmp') | Out-Null
        $env:TEMP=Join-Path $dir 'tmp';$env:TMP=$env:TEMP
        $sources=@()
        foreach($name in $rtlNames){
            if($variant -eq 'corrected'){$sources+=Join-Path $RepoRoot "safevision/rtl/memory/$name.v"}
            else {
                $old=& $GitExe -C $RepoRoot show "d6f40a69ee7865906ec00de54424d9996e759e06:safevision/rtl/memory/$name.v"
                if($LASTEXITCODE -ne 0){throw 'Negative controls require the audited baseline commit in Git history'}
                $path=Join-Path $dir "$name.v"
                [IO.File]::WriteAllText($path,($old -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
                $sources+=$path
            }
        }
        Push-Location -LiteralPath $dir
        try {
            & (Join-Path $XSimBin 'xvlog.bat') -i (Join-Path $RepoRoot 'safevision/rtl/include') @sources --log rtl.log > rtl.console.log 2>&1
            if($LASTEXITCODE -ne 0){throw "$variant RTL compile failed"}
            $runTops=if($variant -eq 'corrected'){$tops}else{@($oldFailures.Keys | Sort-Object)}
            foreach($top in $runTops){
                & (Join-Path $XSimBin 'xvlog.bat') --sv (Join-Path $RepoRoot "safevision/verification/unit/$top.sv") --log "${top}_tb.log" > "${top}_compile.console.log" 2>&1
                if($LASTEXITCODE -ne 0){throw "$top TB compile failed"}
                & (Join-Path $XSimBin 'xelab.bat') "work.$top" -s $top --timescale '1ns/1ps' --log "${top}_elab.log" > "${top}_elab.console.log" 2>&1
                if($LASTEXITCODE -ne 0){throw "$top elaboration failed"}
                & (Join-Path $XSimBin 'xsim.bat') $top -runall --log "${top}_sim.log" > "${top}_sim.console.log" 2>&1
                $exit=$LASTEXITCODE
                $log=Get-Content -LiteralPath "${top}_sim.log" -Raw
                if($variant -eq 'corrected'){
                    if($exit -ne 0 -or $log -notmatch "PASS ${top}:" -or $log -match '(?im)^\s*(Fatal:|FATAL|ERROR:|\[FAIL\])'){throw "$top failed; inspect $dir"}
                    $log -split "`n" | Where-Object {$_ -match "PASS ${top}:"}
                }else{
                    if($log -notmatch "Fatal: $($oldFailures[$top])" -or $log -match "PASS ${top}:"){throw "$top negative control failed to detect the old defect"}
                    Write-Output "VERIFIED old-code negative control: $top"
                }
            }
        }finally{Pop-Location}
    }
    Write-Output "PASS memory protocol regression: corrected=$($tops.Count), old-code negative controls enabled=$(-not $SkipNegativeControls)"
}finally{$env:TEMP=$previousTemp;$env:TMP=$previousTmp}
