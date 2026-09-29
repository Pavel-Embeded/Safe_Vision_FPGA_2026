# ASCII only for Windows PowerShell 5.1 compatibility.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$required = @(
    'README.md', 'docs/PROJECT_STRUCTURE.md', 'docs/interface_spec.md',
    'docs/architecture/module_registry.md', 'docs/requirements/traceability.md',
    'docs/verification/test_matrix.md', 'safevision/rtl/top/README.md',
    'safevision/rtl/video/README.md', 'safevision/rtl/control/README.md',
    'safevision/platform/anlogic_eg4s20_hx4s20c/constraints/README.md',
    'safevision/rtl/storage/spi_master.v',
    'safevision/verification/unit/tb_sd_sector_reader.sv',
    'evidence/README.md'
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) { $missing += $rel }
}
$runner = Join-Path $root 'safevision/tools/run_sim.ps1'
if (Test-Path -LiteralPath $runner) {
    $sv = Join-Path $root 'safevision'
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($runner), '"(\.\./rtl/[^\"]+|models/[^\"]+|unit/[^\"]+)"')) {
        $rel = $m.Groups[1].Value
        $base = Join-Path $sv 'verification'
        if (-not (Test-Path -LiteralPath (Join-Path $base $rel))) { $missing += "run_sim: $rel" }
    }
} else { $missing += 'safevision/tools/run_sim.ps1' }
if ($missing.Count -gt 0) {
    $missing | ForEach-Object { Write-Error "MISSING $_" }
    exit 1
}
Write-Output 'LAYOUT PASS: required paths and run_sim file references exist.'
