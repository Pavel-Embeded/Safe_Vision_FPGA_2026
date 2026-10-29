                                                                         
                                                             
function Write-XSimProject {
 param([string[]]$Paths,[string]$Path)
 $lines=@($Paths | Select-Object -Unique | ForEach-Object {
  $full=[IO.Path]::GetFullPath($_).Replace('\','/')
  if($full -match '["\r\n]'){throw "Unsupported HDL path: $full"}
  if(-not(Test-Path -LiteralPath $full)){throw "Missing HDL source: $full"}
  '"'+$full+'"'
 })
 $target=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
 [IO.File]::WriteAllLines($target,$lines,[Text.UTF8Encoding]::new($false))
}
