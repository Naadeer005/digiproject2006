param([string]$QuartusBin = 'C:/altera_lite/25.1std/quartus/bin64')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
  & (Join-Path $QuartusBin 'quartus_sh.exe') --flow compile memory_match
  if ($LASTEXITCODE -ne 0) { throw "Quartus compilation failed ($LASTEXITCODE)" }
  $timingReport = Join-Path $projectRoot 'output_files/memory_match.sta.rpt'
  if (-not (Test-Path -LiteralPath $timingReport)) { throw 'Timing report is missing' }
  if (Select-String -LiteralPath $timingReport -Pattern 'Timing requirements not met' -Quiet) {
    throw 'Compilation completed, but timing failed. Do not use this build on hardware.'
  }
} finally { Pop-Location }
