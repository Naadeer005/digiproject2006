# Saves the Waveform Editor window to waveforms/png/<Name>.png at native resolution.
# Uses PrintWindow so other windows on top of it are not captured.
param([Parameter(Mandatory)][string]$Name)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static IntPtr Find(string text) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      var s = new StringBuilder(512);
      GetWindowText(h, s, 512);
      if (IsWindowVisible(h) && s.ToString().Contains(text)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
[Win]::SetProcessDPIAware() | Out-Null
$window = [Win]::Find('(Read-Only)')
if ($window -eq [IntPtr]::Zero) { throw 'No read-only Simulation Waveform Editor window is open' }
$rect = New-Object Win+RECT
[Win]::GetWindowRect($window, [ref]$rect) | Out-Null
$bitmap = New-Object System.Drawing.Bitmap ($rect.R - $rect.L), ($rect.B - $rect.T)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$dc = $graphics.GetHdc()
$ok = [Win]::PrintWindow($window, $dc, 2)  # 2 = PW_RENDERFULLCONTENT
$graphics.ReleaseHdc($dc)
if (-not $ok) { throw 'PrintWindow failed' }
$folder = Join-Path $PSScriptRoot 'png'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$path = Join-Path $folder "$Name.png"
$bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bitmap.Dispose()
"$path $($rect.R - $rect.L)x$($rect.B - $rect.T)"
