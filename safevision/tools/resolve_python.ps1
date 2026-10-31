function Resolve-SafeVisionPython {
 param([string]$Python='python')
 $candidates=if($Python -eq 'python'){@('python','python3')}else{@($Python)}
 foreach($candidate in $candidates){
  if(Test-Path -LiteralPath $candidate -PathType Leaf){
   return (Resolve-Path -LiteralPath $candidate).Path
  }
  foreach($command in @(Get-Command $candidate -CommandType Application -All -ErrorAction SilentlyContinue)){
   if($command.Source -notmatch '[\\/]WindowsApps[\\/]'){return $command.Source}
  }
 }
 throw 'Python 3 was not found. Install Python on PATH or pass -Python with its executable path.'
}
