# ============================================================================
# capture_uart_512.ps1 - capture the 512 bytes sent by top_stage5_sector_rd
# ----------------------------------------------------------------------------
# ASCII only: PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so non-ASCII
# comments can swallow the following quote and break parsing. Keep it ASCII.
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File .\safevision\verification\board\capture_uart_512.ps1 -Port COM5
#   powershell -ExecutionPolicy Bypass -File .\safevision\verification\board\capture_uart_512.ps1 -Port COM5 -TimeoutSec 60
#
# What it does:
#   1. lists the available COM ports
#   2. opens <Port> at 115200 8N1, no flow control, and flushes stale input
#   3. waits up to -TimeoutSec for exactly 512 bytes
#   4. saves them as raw binary (NOT text) and compares byte by byte with -Ref
#   5. exit 0 only if all 512 bytes match
#
# *** ORDER MATTERS ***
# The design sends the 512 bytes only ONCE, about 50 ms after reset, and the
# burst lasts about 45 ms (115200 baud). If the LED already shows the done code
# then the burst is long gone. So: start this script FIRST, and only then press
# the board reset key (KEY_1) to run it again.
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [int]$Baud = 115200,
    [int]$TimeoutSec = 30,
    [string]$Out,
    [string]$Ref
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not $Out) { $Out = Join-Path $root ('evidence\board\uart_capture_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.bin') }
if (-not $Ref) { $Ref = Join-Path $root 'evidence\board\lba8192_pc_20261002.bin' }

Write-Output '=== available COM ports ==='
foreach ($p in [System.IO.Ports.SerialPort]::GetPortNames()) { Write-Output ("  " + $p) }
Write-Output ''

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.ReadTimeout = 500

try {
    $sp.Open()
}
catch {
    Write-Output ("FAIL: cannot open {0} - {1}" -f $Port, $_.Exception.Message)
    Write-Output 'Hint: check the COM number, and close any other program that holds the port.'
    exit 2
}

$buf = New-Object byte[] 512
$got = 0
try {
    $sp.DiscardInBuffer()
    Write-Output ("opened {0} at {1} 8N1" -f $Port, $Baud)
    Write-Output '*** Press the board reset key (KEY_1) NOW ***'
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($got -lt 512 -and (Get-Date) -lt $deadline) {
        try {
            $n = $sp.Read($buf, $got, 512 - $got)
            if ($n -gt 0) { $got += $n; Write-Output ("  ... {0}/512 bytes" -f $got) }
        }
        catch [System.TimeoutException] {
            continue
        }
    }
}
finally {
    $sp.Close()
}

if ($got -eq 0) {
    Write-Output 'FAIL: no bytes received within the timeout.'
    Write-Output 'Checklist: right USB port picked (USB-UART, not USB-JTAG); 115200 8N1;'
    Write-Output 'card inserted; reset pressed AFTER this script started.'
    exit 1
}

[IO.File]::WriteAllBytes($Out, $buf[0..($got - 1)])
Write-Output ''
Write-Output ("received {0} bytes -> {1}" -f $got, $Out)
Write-Output ("first 16 bytes: " + (($buf[0..15]  | ForEach-Object { $_.ToString('x2') }) -join ' '))
if ($got -ge 512) {
    Write-Output ("last  16 bytes: " + (($buf[496..511] | ForEach-Object { $_.ToString('x2') }) -join ' '))
}

if (-not (Test-Path -LiteralPath $Ref)) {
    Write-Output ("NOTE: reference file not found, skipped comparison: {0}" -f $Ref)
    exit 0
}

$refBytes = [IO.File]::ReadAllBytes($Ref)
Write-Output ''
Write-Output ("reference      : {0} ({1} bytes)" -f $Ref, $refBytes.Length)
if ($got -ne $refBytes.Length) {
    Write-Output ("FAIL: got {0} bytes, reference has {1} bytes." -f $got, $refBytes.Length)
    exit 1
}

$bad = 0
for ($i = 0; $i -lt $got; $i++) {
    if ($buf[$i] -ne $refBytes[$i]) {
        $bad++
        if ($bad -le 10) { Write-Output ("  diff at byte {0}: got {1:x2}, expected {2:x2}" -f $i, $buf[$i], $refBytes[$i]) }
    }
}

Write-Output ''
if ($bad -eq 0) {
    Write-Output 'PASS: all 512 bytes match the reference (todo list M-9).'
    exit 0
}
Write-Output ("FAIL: {0} of {1} bytes differ." -f $bad, $got)
exit 1