# Same steps as University VWF "Run Functional Simulation", scripted, then checks results.
param(
  [string]$QuartusBin = 'C:/altera_lite/25.1std/quartus/bin64',
  [string]$QuestaBin = 'C:/altera_lite/25.1std/questa_fse/win64',
  [string[]]$Blocks = @('game_core','input_controller','vga_timing','frame_snapshot','top'),
  [string[]]$Skip = @()
)
$ErrorActionPreference = 'Stop'
$env:PATH = "$QuartusBin;$QuestaBin;$env:PATH"
function Run([string]$program) {
  & $program @args 2>&1 | Out-File -Append -Encoding utf8 run.log
  if ($LASTEXITCODE -ne 0) { throw "$program failed ($LASTEXITCODE), see $(Get-Location)/run.log" }
}
foreach ($block in $Blocks) {
  $top = "vwf_$block"
  $dir = Join-Path $PSScriptRoot $block
  Push-Location $dir
  try {
    Remove-Item run.log -ErrorAction SilentlyContinue
    Run quartus_map $top -c $top
    Run quartus_eda --write_settings_files=off --simulation --functional=on --flatten_buses=off --tool=modelsim_oem --format=vhdl --output_directory=./simulation/qsim/ $top -c $top
    foreach ($vwf in Get-ChildItem *.vwf) {
      $name = $vwf.BaseName
      if ($Skip -contains $name) { continue }
      Run quartus_eda --gen_testbench --tool=modelsim_oem --format=vhdl --write_settings_files=off $top -c $top "--vector_source=$($vwf.Name)" "--testbench_file=./simulation/qsim/$name.vwf.vht"
      Push-Location simulation/qsim
      try {
        # Generated "16866000000 ps" overflows VHDL INTEGER past 2.1 ms (tc17); same time in us fits.
        (Get-Content "$name.vwf.vht") -replace '\b(\d+)000000 ps\b', '$1 us' | Set-Content "$name.vwf.vht"
        @"
onerror {exit -code 1}
vlib work
vcom -work work $top.vho
vcom -work work $name.vwf.vht
vsim -c -t 1ps -voptargs=+acc -L fiftyfivenm -L altera -L altera_mf -L 220model -L sgate -L altera_lnsim work.${top}_vhd_vec_tst
vcd file -direction $name.msim.vcd
vcd add -internal ${top}_vhd_vec_tst/*
run -all
quit -f
"@ | Set-Content "$name.do" -Encoding ascii
        & vsim -c -do "$name.do" 2>&1 | Out-File -Append -Encoding utf8 ../../run.log
        if ($LASTEXITCODE -ne 0) { throw "vsim failed for $name" }
      } finally { Pop-Location }
      Write-Host "simulated $name"
    }
  } finally { Pop-Location }
}
python (Join-Path $PSScriptRoot 'gen_vwf.py') --check
