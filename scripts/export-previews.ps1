# Convert PPM images produced by tb_video into PNG without external libraries.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Drawing
$destination = Join-Path $projectRoot 'docs/previews'
New-Item -ItemType Directory -Force $destination | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build/sim') -Filter '*.ppm' | ForEach-Object {
  $reader = [System.IO.StreamReader]::new($_.FullName)
  try {
    if ($reader.ReadLine() -ne 'P3') { throw 'Expected P3 PPM' }
    $dimensions = $reader.ReadLine().Split(' ')
    $width = [int]$dimensions[0]; $height = [int]$dimensions[1]
    if ($reader.ReadLine() -ne '255') { throw 'Expected 8-bit color' }
    $bitmap = [System.Drawing.Bitmap]::new($width,$height)
    try {
      for ($row = 0; $row -lt $height; $row++) {
        $values = $reader.ReadLine().Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)
        for ($col = 0; $col -lt $width; $col++) {
          $offset = $col*3
          $bitmap.SetPixel($col,$row,[System.Drawing.Color]::FromArgb([int]$values[$offset],[int]$values[$offset+1],[int]$values[$offset+2]))
        }
      }
      $bitmap.Save((Join-Path $destination ($_.BaseName+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
  } finally { $reader.Dispose() }
}
