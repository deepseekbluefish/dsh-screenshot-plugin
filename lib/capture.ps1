# capture.ps1 - host-side capture script for the DSH in-app screenshot plugin.
# STRICTLY ASCII: Windows PowerShell 5.1 reads non-BOM UTF-8 as ANSI and can
# swallow newlines after multi-byte chars, eating code lines. No non-ASCII here.
# Params: -Folder <save dir> ; stdout emits JSON: {ok,file,marker} or {ok:false,cancelled:true}
param([string]$Folder = 'C:\Users\Public\Pictures\DSH-Screenshots')
$ErrorActionPreference = 'Stop'

# CJK constant via char codes (Jie=U+622A, Ping=U+5C4F) - filename prefix only.
# The chat marker is pure ASCII: [Shot N HH:mm]
$CJ = [string]([char]0x622A) + [string]([char]0x5C4F)  # "JiePing" (screenshot)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class DpiH {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[DpiH]::SetProcessDPIAware() | Out-Null

# Counter file (ASCII name on purpose)
$CounterFile = Join-Path $Folder '.screenshot-counter.txt'

function Get-NextNumber {
    if (Test-Path -LiteralPath $CounterFile) {
        $raw = (Get-Content -LiteralPath $CounterFile -Raw).Trim()
        $v = 0
        if ([int]::TryParse($raw, [ref]$v) -and $v -ge 1) { return $v }
    }
    return 1
}

function Save-And-Emit([System.Drawing.Bitmap]$bmp) {
    $n = Get-NextNumber
    $stamp = Get-Date -Format 'HHmm'
    $name = "$CJ$n" + "_$stamp.png"
    $path = Join-Path $Folder $name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Set-Content -LiteralPath $CounterFile -Value ($n + 1) -NoNewline -Encoding ASCII
    $hhmm = Get-Date -Format 'HH:mm'
    $marker = "[Shot $n $hhmm]"
    # NOTE: no Write-Output here - event-handler output is discarded by the
    # engine. The caller stores the result and emits it from the main flow.
    return @{ ok = $true; file = $name; path = $path; marker = $marker }
}

$script:selStart = $null
$script:selCur   = $null
$script:captured = $false
$script:result   = $null

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$ov = New-Object System.Windows.Forms.Form
$ov.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$ov.Bounds = $vs
$ov.TopMost = $true
$ov.ShowInTaskbar = $false
$ov.BackColor = [System.Drawing.Color]::Black
$ov.Opacity = 0.28
$ov.Cursor = [System.Windows.Forms.Cursors]::Cross

$ov.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:selStart = New-Object System.Drawing.Point($e.X, $e.Y)
        $script:selCur = $script:selStart
    }
})
$ov.Add_MouseMove({
    param($s, $e)
    if ($null -ne $script:selStart) {
        $script:selCur = New-Object System.Drawing.Point($e.X, $e.Y)
        $ov.Invalidate()
    }
})
$ov.Add_Paint({
    param($s, $e)
    if ($null -ne $script:selStart -and $null -ne $script:selCur) {
        $x = [Math]::Min($script:selStart.X, $script:selCur.X)
        $y = [Math]::Min($script:selStart.Y, $script:selCur.Y)
        $w = [Math]::Abs($script:selCur.X - $script:selStart.X)
        $h = [Math]::Abs($script:selCur.Y - $script:selStart.Y)
        if ($w -gt 0 -and $h -gt 0) {
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 0, 150, 255), 2)
            $e.Graphics.DrawRectangle($pen, $x, $y, $w, $h)
            $pen.Dispose()
        }
    }
})
$ov.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $x1 = [Math]::Min($script:selStart.X, $script:selCur.X)
    $y1 = [Math]::Min($script:selStart.Y, $script:selCur.Y)
    $w  = [Math]::Abs($script:selCur.X - $script:selStart.X)
    $h  = [Math]::Abs($script:selCur.Y - $script:selStart.Y)
    $ov.Hide()
    $script:selStart = $null; $script:selCur = $null
    if ($w -ge 8 -and $h -ge 8) {
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($ov.Left + $x1, $ov.Top + $y1, 0, 0, (New-Object System.Drawing.Size($w, $h)))
        $g.Dispose()
        $script:result = Save-And-Emit $bmp
        $bmp.Dispose()
        $script:captured = $true
    }
    $ov.Close()
})
$ov.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:selStart = $null; $script:selCur = $null
        $ov.Close()
    }
})

$ov.Show()
$ov.Activate()
[System.Windows.Forms.Application]::Run($ov)

# Emit the JSON from the MAIN flow (event-handler output would be discarded).
if ($null -ne $script:result) {
    Write-Output (ConvertTo-Json -Compress $script:result)
}
elseif (-not $script:captured) {
    Write-Output (ConvertTo-Json -Compress @{ ok = $false; cancelled = $true })
}
