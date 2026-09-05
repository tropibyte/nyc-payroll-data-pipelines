<#
.SYNOPSIS
    Capture a browser window to a PNG in screenshots/.

.DESCRIPTION
    The proof-of-work captures this project needs have to be real screenshots
    of the Azure portal, and the browser-automation tooling can return an image
    without being able to write it to disk. This closes that gap: it brings the
    target window to the foreground and grabs its client area straight from the
    screen, so the file lands where the submission checklist expects it.

    Captures the window rectangle rather than the whole desktop, so nothing
    else on screen leaks into the shot.

.PARAMETER Name
    Output filename. ".png" is appended if missing. Written to screenshots/.

.PARAMETER TitleMatch
    Substring of the window title to capture. Defaults to Chrome showing Azure.

.EXAMPLE
    ./scripts/capture_screen.ps1 01-adls-dirpayrollfiles
    ./scripts/capture_screen.ps1 15-pipeline-canvas -TitleMatch "Data Factory"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$TitleMatch = 'Azure',
    # Title alone is ambiguous -- Edge and Chrome can both be showing "Azure".
    [string]$ProcessName = 'chrome',
    [int]$DelayMs = 900
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not ('Win32Capture' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32Capture {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
}

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'screenshots'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (-not $Name.EndsWith('.png')) { $Name = "$Name.png" }
$out = Join-Path $outDir $Name

# Pick the best-matching visible window.
$candidates = Get-Process | Where-Object {
    $_.MainWindowHandle -ne 0 -and
    $_.MainWindowTitle -like "*$TitleMatch*" -and
    ($ProcessName -eq '' -or $_.ProcessName -eq $ProcessName)
}
$proc = $candidates | Select-Object -First 1
if (-not $proc) {
    $names = (Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } |
              ForEach-Object { "$($_.ProcessName): $($_.MainWindowTitle)" }) -join "`n  "
    throw "no '$ProcessName' window matching '*$TitleMatch*'. Open windows:`n  $names"
}

$h = $proc.MainWindowHandle
if ([Win32Capture]::IsIconic($h)) { [void][Win32Capture]::ShowWindow($h, 9) }  # SW_RESTORE
[void][Win32Capture]::SetForegroundWindow($h)
Start-Sleep -Milliseconds $DelayMs

$r = New-Object Win32Capture+RECT
if (-not [Win32Capture]::GetWindowRect($h, [ref]$r)) { throw "GetWindowRect failed" }
$w = $r.Right - $r.Left
$hgt = $r.Bottom - $r.Top
if ($w -le 0 -or $hgt -le 0) { throw "window has no size ($w x $hgt)" }

$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "saved $out  ($w x $hgt)  from '$($proc.MainWindowTitle)'"
