$ErrorActionPreference='Stop'
python -B (Join-Path $PSScriptRoot 'check_source_tree.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
