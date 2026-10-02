param(
  [ValidateSet('questa','ghdl')][string]$Simulator = 'questa',
  [ValidateSet('tb_game_core','tb_input_controller','tb_video','tb_top')]
  [string[]]$Benches = @('tb_game_core','tb_input_controller','tb_video','tb_top')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$simulationDir = Join-Path $projectRoot 'build/sim'
New-Item -ItemType Directory -Force -Path $simulationDir | Out-Null
$sources = @('rtl/game_pkg.vhd','rtl/font_pkg.vhd','rtl/input_controller.vhd',
  'rtl/game_core.vhd','rtl/vga_timing.vhd','rtl/frame_snapshot.vhd','rtl/renderer.vhd','rtl/top.vhd',
  'sim/tb_game_core.vhd','sim/tb_input_controller.vhd','sim/tb_video.vhd','sim/tb_top.vhd')
function Invoke-Checked([string]$program, [string[]]$arguments) {
  & $program @arguments
  if ($LASTEXITCODE -ne 0) { throw "$program failed with exit code $LASTEXITCODE" }
}
Push-Location $simulationDir
try {
  if ($Simulator -eq 'questa') {
    Invoke-Checked 'vlib' @('work')
    $absoluteSources = $sources | ForEach-Object { Join-Path $projectRoot $_ }
    Invoke-Checked 'vcom' (@('-2008','-work','work') + $absoluteSources)
    foreach ($bench in $Benches) {
      # Stop on severity failure; onfinish exit preserves assertion exit codes.
      $doFile = (Join-Path $projectRoot 'sim/run.do').Replace('\','/')
      $commands = "do {$doFile}"
      Invoke-Checked 'vsim' @('-c','-onfinish','exit','-wlf',"$bench.wlf",'-l',"$bench.log","work.$bench",'-do',$commands)
    }
  } else {
    foreach ($source in $sources) { Invoke-Checked 'ghdl' @('-a','--std=08',(Join-Path $projectRoot $source)) }
    foreach ($bench in $Benches) {
      Invoke-Checked 'ghdl' @('-e','--std=08',$bench)
      Invoke-Checked 'ghdl' @('-r','--std=08',$bench,'--assert-level=error',"--wave=$bench.ghw")
    }
  }
} finally { Pop-Location }
