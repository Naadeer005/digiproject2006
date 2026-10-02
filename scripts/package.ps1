# Package source, reports, simulation evidence and the compiled SRAM image.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$timingReport = Join-Path $projectRoot 'output_files/memory_match.sta.rpt'
if (-not (Test-Path -LiteralPath $timingReport)) { throw 'Compile the project first.' }
if (Select-String -LiteralPath $timingReport -Pattern 'Timing requirements not met' -Quiet) {
  throw 'Refusing to package a build with failing timing.'
}
foreach ($bench in @('tb_game_core','tb_input_controller','tb_video','tb_top')) {
  $log = Join-Path $projectRoot "build/sim/$bench.log"
  if (-not (Test-Path -LiteralPath $log)) { throw "Run $bench first." }
  if (-not (Select-String -LiteralPath $log -Pattern "PASS $bench" -Quiet)) { throw "$bench has no passing result." }
}
$packageRoot = Join-Path $projectRoot 'build/submission/memory_match'
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
foreach ($item in @('rtl','constraints','sim','scripts','docs','README.md','memory_match.qpf','memory_match.qsf','.gitignore')) {
  Copy-Item -LiteralPath (Join-Path $projectRoot $item) -Destination $packageRoot -Recurse -Force
}
$outputFolder = Join-Path $packageRoot 'output_files'
$evidenceFolder = Join-Path $packageRoot 'build/sim'
New-Item -ItemType Directory -Force $outputFolder,$evidenceFolder | Out-Null
foreach ($name in @('memory_match.sof','memory_match.fit.summary','memory_match.sta.rpt')) {
  Copy-Item -LiteralPath (Join-Path $projectRoot "output_files/$name") -Destination $outputFolder -Force
}
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build/sim') -File |
  Where-Object { $_.Extension -in @('.log','.wlf','.ghw') } |
  Copy-Item -Destination $evidenceFolder -Force
foreach ($name in @('critical_paths.txt','unconstrained_paths.txt','compile.log')) {
  $evidence = Join-Path $projectRoot "build/$name"
  if (Test-Path -LiteralPath $evidence) {
    Copy-Item -LiteralPath $evidence -Destination (Join-Path $packageRoot 'build') -Force
  }
}
Compress-Archive -LiteralPath $packageRoot -DestinationPath (Join-Path $projectRoot 'build/memory_match_submission.zip') -Force
Write-Output 'Created build/memory_match_submission.zip'
