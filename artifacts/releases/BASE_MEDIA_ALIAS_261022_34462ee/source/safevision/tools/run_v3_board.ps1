param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [Parameter(Mandatory=$true)][string]$RunDir,
 [string]$TdRoot='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116',
 [string[]]$Mode=@('base','hd'),[switch]$Bitgen,[switch]$SynthOnly,
 [string]$SourceRepo,[string]$SourceRef='HEAD',
 [string]$Python=(Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
)
$ErrorActionPreference='Stop'
$v3Args=@((Join-Path $PSScriptRoot 'run_v3_board.py'),'--repo',$RepoRoot,'--run-dir',$RunDir,'--td-root',$TdRoot)
foreach($v3Mode in $Mode){$v3Args+=@('--mode',$v3Mode)}
if($Bitgen){$v3Args+='--bitgen'}
if($SynthOnly){$v3Args+='--synth-only'}
if($SourceRepo){$v3Args+=@('--source-repo',$SourceRepo)}
$v3Args+=@('--source-ref',$SourceRef)
& $Python @v3Args
if($LASTEXITCODE){throw "V3 build/gate failed (exit $LASTEXITCODE); see raw reports and build.manifest.json in $RunDir"}
