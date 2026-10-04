param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$TdRoot = 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
    [string]$ProjectDir = '',
    [string]$RunDir = '',
    [ValidateSet('both','base','hd')][string]$Mode = 'both'
)
# ASCII-only runner. Exit 0 = internal paths met and no health warning;
# exit 2 = internal timing met but TD health warnings remain; exit 1 = failure.
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $ProjectDir) {
    $ProjectDir = Join-Path $RepoRoot 'safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify'
}
if (-not $RunDir) {
    $RunDir = Join-Path $RepoRoot 'safevision/build/out/clock_video_verify'
}
$ProjectDir = [IO.Path]::GetFullPath($ProjectDir)
$RunDir = [IO.Path]::GetFullPath($RunDir)
$svTdExe = Join-Path $TdRoot 'bin/td_commands_prompt.exe'
foreach ($svRequired in @($svTdExe, (Join-Path $ProjectDir 'td_flow.tcl'),
    (Join-Path $ProjectDir 'postroute.tcl'))) {
    if (-not (Test-Path -LiteralPath $svRequired -PathType Leaf)) {
        throw "Missing TD input: $svRequired"
    }
}
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$svOldRepo = $env:SAFEVISION_REPO
$svOldOut = $env:SAFEVISION_VERIFY_OUT
$svHasWarnings = $false
$svRows = @()
function Invoke-SvTdStage([string]$svEntry, [string]$svLog) {
    & $svTdExe $svEntry 2>&1 | Tee-Object -FilePath $svLog | Out-Host
    $svExit = $LASTEXITCODE
    $svText = Get-Content -LiteralPath $svLog -Raw
    if ($svExit -ne 0 -or $svText -match '(?m)\bERROR:|TD (?:FLOW|POSTROUTE) FAILED|Oops! coredump') {
        throw "TD failed: entry=$svEntry exit=$svExit log=$svLog"
    }
    if ($svText -notmatch 'TD (?:FLOW|POSTROUTE) COMPLETE') {
        throw "TD completion marker missing: $svLog"
    }
}
try {
    $env:SAFEVISION_REPO = $RepoRoot.Replace('\','/')
    $env:SAFEVISION_VERIFY_OUT = $RunDir.Replace('\','/')
    $svModes = if ($Mode -eq 'both') { @('base','hd') } else { @($Mode) }
    Push-Location -LiteralPath $ProjectDir
    try {
        foreach ($svMode in $svModes) {
            $svModeOut = Join-Path $RunDir $svMode
            New-Item -ItemType Directory -Force -Path $svModeOut | Out-Null
            $svFlowLog = Join-Path $svModeOut 'flow.console.log'
            $svPostLog = Join-Path $svModeOut 'postroute.console.log'
            Invoke-SvTdStage "./$svMode.tcl" $svFlowLog
            # Separate process after the synthesis process exits/releases license.
            Invoke-SvTdStage "./${svMode}_postroute.tcl" $svPostLog
            $svFinal = Join-Path $svModeOut 'postroute'
            foreach ($svName in @('final.timing','final.status','final.clock_summary',
                'final.clock_intersection','final.check_timing','final.area',
                'final.exceptions','final.ignored','final.derived.sdc')) {
                $svReport = Join-Path $svFinal $svName
                if (-not (Test-Path -LiteralPath $svReport -PathType Leaf)) {
                    throw "Missing final TD report: $svReport"
                }
            }
            [xml]$svXml = Get-Content -LiteralPath (Join-Path $svFinal 'final.clock_summary') -Raw
            $svClocks = @($svXml.SelectNodes('//clock'))
            if ($svClocks.Count -ne 8) { throw "Expected 8 clocks; found $($svClocks.Count): $svMode" }
            $svMaster = @($svClocks | Where-Object { $_.name -eq 'board_clk_50' })
            if ($svMaster.Count -ne 1 -or $svMaster[0].type -ne 'primary') {
                throw "Missing/invalid 50 MHz master clock: $svMode"
            }
            $svPrefix = 'u_subsystem/u_clock_gen/'
            $svVideoBranch = if ($svMode -eq 'base') { 'gen_video_base' } else { 'gen_video_hd' }
            $svVideoPrefix = $svPrefix + $svVideoBranch + '$u_video_pll/pll_inst.clkc'
            $svPixelMHz = if ($svMode -eq 'base') { 25.185185185 } else { 74.166666667 }
            $svSerialMHz = if ($svMode -eq 'base') { 125.925925926 } else { 370.833333333 }
            $svFeedbackMHz = if ($svMode -eq 'base') { 283.333333333 } else { 12.5 }
            $svTotalLeaves = if ($svMode -eq 'base') { 54 } else { 58 }
            $svExpected = @{
                'board_clk_50' = 50.0
                ($svPrefix + 'u_system_pll/pll_inst.clkc[0]') = 100.0
                ($svPrefix + 'u_system_pll/pll_inst.clkc[1]') = 125.0
                ($svVideoPrefix + '[1]') = $svPixelMHz
                ($svVideoPrefix + '[2]') = $svSerialMHz
                ($svVideoPrefix + '[0]') = $svFeedbackMHz
                ($svPrefix + 'u_audio_pll/pll_inst.clkc[1]') = 12.288135593
                ($svPrefix + 'u_audio_pll/pll_inst.clkc[0]') = 25.0
            }
            # Reviewed TD6.2 footprint after the NORMAL feedback-wiring repair.
            # Pixel-domain FF packing uses one fewer shared physical clock pin.
            # Register bits remain 68/71 (BASE/HD); check both counts below so
            # a lost register cannot be accepted as a mere packing change.
            $svExpectedLeaves = @{
                'board_clk_50' = $svTotalLeaves
                ($svPrefix + 'u_system_pll/pll_inst.clkc[0]') = $(if ($svMode -eq 'base') { 8 } else { 10 })
                ($svPrefix + 'u_system_pll/pll_inst.clkc[1]') = 8
                ($svVideoPrefix + '[1]') = $(if ($svMode -eq 'base') { 28 } else { 30 })
                ($svVideoPrefix + '[2]') = 6
                ($svVideoPrefix + '[0]') = 0
                ($svPrefix + 'u_audio_pll/pll_inst.clkc[1]') = 4
                ($svPrefix + 'u_audio_pll/pll_inst.clkc[0]') = 0
            }
            $svGroups = @($svXml.SelectNodes('/clock_summary/groups/clock_group'))
            if ($svGroups.Count -ne 1 -or $svGroups[0].name -ne 'board_clk_50' -or
                [int]$svGroups[0].size -ne 8 -or [int]$svGroups[0].endpoints -ne $svTotalLeaves -or
                [int]$svGroups[0].clocks -ne $svTotalLeaves -or [int]$svGroups[0].nonclocks -ne 0) {
                throw "Incomplete master/leaf clock group: $svMode"
            }
            foreach ($svClockName in $svExpected.Keys) {
                $svFound = @($svClocks | Where-Object { $_.name -eq $svClockName })
                if ($svFound.Count -ne 1) { throw "Missing clock: $svClockName" }
                $svMHz = [double]($svFound[0].freq -replace 'MHz','')
                # TD quantizes the period to ps (e.g. HD serial shows 370.920).
                # This gate checks the STA profile, not hardware ppm/jitter.
                if ([Math]::Abs($svMHz - $svExpected[$svClockName]) -gt 0.001 * $svExpected[$svClockName]) {
                    throw "Wrong STA frequency: $svClockName $svMHz MHz"
                }
                if ([int]$svFound[0].endpoints -ne $svExpectedLeaves[$svClockName] -or
                    [int]$svFound[0].clocks -ne $svExpectedLeaves[$svClockName] -or
                    [int]$svFound[0].nonclocks -ne 0) {
                    throw "Wrong leaf-clock coverage: $svClockName"
                }
            }
            $svArea = Get-Content -LiteralPath (Join-Path $svFinal 'final.area') -Raw
            $svRegMatch = [regex]::Match($svArea, '(?m)^#reg\s+(\d+)\s+out of')
            $svOregMatch = [regex]::Match($svArea, '(?m)^\s*#oreg\s+(\d+)\s*$')
            $svExpectedRegs = if ($svMode -eq 'base') { 68 } else { 71 }
            if (-not $svRegMatch.Success -or [int]$svRegMatch.Groups[1].Value -ne $svExpectedRegs -or
                -not $svOregMatch.Success -or [int]$svOregMatch.Groups[1].Value -ne 17) {
                throw "Wrong sequential/register-output coverage: $svMode"
            }
            $svTiming = Get-Content -LiteralPath (Join-Path $svFinal 'final.timing') -Raw
            if ($svTiming -match 'DeriveClock' -or $svTiming -notmatch 'Confidence\s+:\s+Routed') {
                throw "Fallback/unrouted timing graph: $svMode"
            }
            foreach ($svType in @('setup','hold','recovery','removal')) {
                if ($svTiming -notmatch "Check Type\s+:\s+$svType\b") {
                    throw "Missing $svType analysis: $svMode"
                }
            }
            $svStatus = Get-Content -LiteralPath (Join-Path $svFinal 'final.status') -Raw
            foreach ($svMetric in @('SWNS','STNS','HWNS','HTNS')) {
                $svMatch = [regex]::Match($svStatus, "$svMetric`:\s*([-\d.]+)ns")
                if (-not $svMatch.Success -or [double]$svMatch.Groups[1].Value -lt 0) {
                    throw "Negative/missing $svMetric in $svMode"
                }
            }
            $svCheck = Get-Content -LiteralPath (Join-Path $svFinal 'final.check_timing') -Raw
            if ($svCheck -notmatch 'checking no clock\(0\)') {
                throw "Untimed clock nets found: $svMode"
            }
            $svLogs = (Get-Content -LiteralPath $svFlowLog -Raw) +
                      (Get-Content -LiteralPath $svPostLog -Raw)
            $svWarn = $svLogs -match 'CRITICAL-WARNING' -or
                      $svCheck -notmatch 'checking clock definition\(0\)'
            if ($svWarn) { $svHasWarnings = $true }
            $svLabel = if ($svWarn) { 'INTERNAL_TIMING_MET_HEALTH_WARNINGS_OPEN' } else { 'INTERNAL_TIMING_MET' }
            $svRows += "$svMode`: $svLabel; clocks=8; $($svStatus.Trim())"
            Write-Host "[RESULT] $($svRows[-1])"
            Write-Host '[BOUNDARY] 5 external inputs and 17 probe outputs have no I/O timing budget.'
        }
    } finally { Pop-Location }
    $svRows | Set-Content -LiteralPath (Join-Path $RunDir 'verification_status.txt') -Encoding utf8
} finally {
    $env:SAFEVISION_REPO = $svOldRepo
    $env:SAFEVISION_VERIFY_OUT = $svOldOut
}
if ($svHasWarnings) {
    Write-Warning 'Internal paths met. TD health warnings remain; review physical-network evidence and final.check_timing.'
    exit 2
}
exit 0
