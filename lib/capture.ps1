# capture.ps1 - host-side capture script for the DSH in-app screenshot plugin.
# STRICTLY ASCII: Windows PowerShell 5.1 reads non-BOM UTF-8 as ANSI and can
# swallow newlines after multi-byte chars, eating code lines. No non-ASCII here.
# Params: -Folder <save dir> [-SelfTest] ; stdout emits JSON:
#   {ok:true,file,path,marker} on capture, {ok:false,cancelled:true} on cancel.
#
# Interaction model:
#   drag on the dimmed screen to draw the initial selection
#   release: the bright-green frame stays; drag inside to move, drag edges or
#            corners (8 handles) to resize
#   double-click inside the frame or press Enter: confirm and capture
#   Esc: cancel
param([string]$Folder = 'C:\Users\Public\Pictures\DSH-Screenshots', [switch]$SelfTest, [string]$DemoRect = '')
$ErrorActionPreference = 'Stop'

# CJK constant via char codes (Jie=U+622A, Ping=U+5C4F) - filename prefix only.
# The chat marker is pure ASCII: [Shot N HH:mm]
$CJ = [string]([char]0x622A) + [string]([char]0x5C4F)  # "JiePing" (screenshot)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' -TypeDefinition @"
using System.Runtime.InteropServices;
public static class DpiH {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
// A click-through, non-activating window: mouse input falls through to the
// veil below while the drawn frame stays crisp and undimmed.
public class PassThroughFrame : System.Windows.Forms.Form {
    [DllImport("user32.dll")] static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
    // Show without taking keyboard focus, so Enter/Esc keep going to the veil.
    public void ShowPassive() {
        if (!this.IsHandleCreated) { this.CreateControl(); }
        this.Visible = true;
        ShowWindow(this.Handle, 4); // SW_SHOWNOACTIVATE
    }
    protected override System.Windows.Forms.CreateParams CreateParams {
        get {
            System.Windows.Forms.CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000020; // WS_EX_TRANSPARENT
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            return cp;
        }
    }
}
"@
[DpiH]::SetProcessDPIAware() | Out-Null

# ---------------- pure geometry helpers (no UI; covered by -SelfTest) ----------------
$HANDLE = 7     # hit tolerance around edges and corners, px
$MIN_W  = 20    # minimum selection size, px
$MIN_H  = 20
$FRAME_MARGIN = 14   # frame form padding around the selection

function New-Rect([int]$x, [int]$y, [int]$w, [int]$h) {
    return @{ X = $x; Y = $y; W = $w; H = $h }
}

function Copy-Rect($r) {
    return @{ X = $r.X; Y = $r.Y; W = $r.W; H = $r.H }
}

# Clamp a rect into [0,maxW]x[0,maxH], honoring the minimum size.
function Clamp-Rect($r, [int]$maxW, [int]$maxH) {
    $x = $r.X; $y = $r.Y; $w = $r.W; $h = $r.H
    if ($w -lt $MIN_W) { $w = $MIN_W }
    if ($h -lt $MIN_H) { $h = $MIN_H }
    if ($x -lt 0) { $x = 0 }
    if ($y -lt 0) { $y = 0 }
    if ($x + $w -gt $maxW) { $x = $maxW - $w; if ($x -lt 0) { $x = 0; $w = $maxW } }
    if ($y + $h -gt $maxH) { $y = $maxH - $h; if ($y -lt 0) { $y = 0; $h = $maxH } }
    return New-Rect $x $y $w $h
}

# What is under the pointer? 'none', 'move', or an edge code (N/S/E/W/NE/NW/SE/SW).
function Hit-Zone([int]$px, [int]$py, $r) {
    $onL = [Math]::Abs($px - $r.X) -le $HANDLE
    $onR = [Math]::Abs($px - ($r.X + $r.W)) -le $HANDLE
    $onT = [Math]::Abs($py - $r.Y) -le $HANDLE
    $onB = [Math]::Abs($py - ($r.Y + $r.H)) -le $HANDLE
    if ($onT -and $onL) { return 'NW' }
    if ($onT -and $onR) { return 'NE' }
    if ($onB -and $onL) { return 'SW' }
    if ($onB -and $onR) { return 'SE' }
    if ($onT) { return 'N' }
    if ($onB) { return 'S' }
    if ($onL) { return 'W' }
    if ($onR) { return 'E' }
    if ($px -gt $r.X -and $px -lt $r.X + $r.W -and $py -gt $r.Y -and $py -lt $r.Y + $r.H) { return 'move' }
    return 'none'
}

# Resize one edge/corner by (dx, dy); returns the new rect.
function Apply-Resize($r, [string]$edge, [int]$dx, [int]$dy, [int]$maxW, [int]$maxH) {
    $x = $r.X; $y = $r.Y; $w = $r.W; $h = $r.H
    if ($edge -like '*E') { $w = $r.W + $dx }
    if ($edge -like '*W') { $x = $r.X + $dx; $w = $r.W - $dx }
    if ($edge -like 'N*') { $y = $r.Y + $dy; $h = $r.H - $dy }
    if ($edge -like 'S*') { $h = $r.H + $dy }
    return Clamp-Rect (New-Rect $x $y $w $h) $maxW $maxH
}

# Move by (dx, dy); returns the new rect.
function Apply-Move($r, [int]$dx, [int]$dy, [int]$maxW, [int]$maxH) {
    return Clamp-Rect (New-Rect ($r.X + $dx) ($r.Y + $dy) $r.W $r.H) $maxW $maxH
}

if ($SelfTest) {
    $fails = @()
    function Assert([bool]$cond, [string]$name) {
        if (-not $cond) { $script:fails += $name }
    }
    $r = Clamp-Rect (New-Rect -5 -10 30 30) 100 100
    Assert ($r.X -eq 0 -and $r.Y -eq 0) 'clamp-negative'
    $r = Clamp-Rect (New-Rect 90 90 30 30) 100 100
    Assert ($r.X -eq 70 -and $r.Y -eq 70) 'clamp-overflow'
    $r = Clamp-Rect (New-Rect 0 0 5 5) 100 100
    Assert ($r.W -eq $MIN_W -and $r.H -eq $MIN_H) 'clamp-min'
    $z = Hit-Zone 4 4 (New-Rect 10 10 50 50)
    Assert ($z -eq 'NW') 'hit-NW'
    $z = Hit-Zone 58 60 (New-Rect 10 10 50 50)
    Assert ($z -eq 'SE') 'hit-SE'
    $z = Hit-Zone 35 8 (New-Rect 10 10 50 50)
    Assert ($z -eq 'N') 'hit-N'
    $z = Hit-Zone 35 30 (New-Rect 10 10 50 50)
    Assert ($z -eq 'move') 'hit-move'
    $z = Hit-Zone 70 70 (New-Rect 10 10 50 50)
    Assert ($z -eq 'none') 'hit-none'
    $r = Apply-Resize (New-Rect 10 10 50 50) 'E' 10 0 200 200
    Assert ($r.W -eq 60 -and $r.X -eq 10) 'resize-E'
    $r = Apply-Resize (New-Rect 10 10 50 50) 'W' 10 0 200 200
    Assert ($r.W -eq 40 -and $r.X -eq 20) 'resize-W'
    $r = Apply-Resize (New-Rect 10 10 50 50) 'N' 0 10 200 200
    Assert ($r.H -eq 40 -and $r.Y -eq 20) 'resize-N'
    $r = Apply-Resize (New-Rect 10 10 50 50) 'SE' -100 -100 200 200
    Assert ($r.W -ge $MIN_W -and $r.H -ge $MIN_H) 'resize-min'
    $r = Apply-Move (New-Rect 10 10 50 50) 5 5 100 100
    Assert ($r.X -eq 15 -and $r.Y -eq 15) 'move'
    $r = Apply-Move (New-Rect 60 60 50 50) 50 50 100 100
    Assert ($r.X -eq 50 -and $r.Y -eq 50) 'move-clamp'
    if ($fails.Count -eq 0) {
        Write-Output '{"selftest":"ok"}'
    } else {
        Write-Output ('{"selftest":"fail","fails":["' + ($fails -join '","') + '"]}')
        exit 1
    }
    exit 0
}

# ---------------- capture plumbing ----------------
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

# ---------------- UI state ----------------
$script:mode = 'none'      # none | drawing | adjust | moving | resizing
$script:rect = $null       # current selection: hashtable X Y W H
$script:selStart = $null
$script:selCur = $null
$script:dragBase = $null
$script:dragRect = $null
$script:dragEdge = $null
$script:captured = $false
$script:result = $null
$script:frameTopPad = $FRAME_MARGIN   # local Y of the rect inside the frame form

$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$maxW = $vs.Width
$maxH = $vs.Height

$GREEN = [System.Drawing.Color]::FromArgb(255, 0, 255, 0)
$WHITE = [System.Drawing.Color]::White

# ---------------- veil (receives all input) ----------------
$ov = New-Object System.Windows.Forms.Form
$ov.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$ov.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$ov.Bounds = $vs
$ov.TopMost = $true
$ov.ShowInTaskbar = $false
$ov.BackColor = [System.Drawing.Color]::Black
$ov.Opacity = 0.35
$ov.Cursor = [System.Windows.Forms.Cursors]::Cross

# ---------------- frame (crisp bright-green frame, click-through) ----------------
$frame = New-Object PassThroughFrame
$frame.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$frame.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$frame.ShowInTaskbar = $false
$frame.TopMost = $true
$frame.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$frame.BackColor = [System.Drawing.Color]::Magenta
$frame.TransparencyKey = [System.Drawing.Color]::Magenta
$frame.Hide()

function Update-Frame {
    if ($null -eq $script:rect) {
        if ($frame.Visible) { $frame.Hide() }
        return
    }
    $r = $script:rect
    $script:frameTopPad = $FRAME_MARGIN
    $fx = $vs.Left + $r.X - $FRAME_MARGIN
    $fy = $vs.Top + $r.Y - $script:frameTopPad
    $fw = $r.W + 2 * $FRAME_MARGIN
    $fh = $r.H + 2 * $FRAME_MARGIN
    $frame.SetBounds($fx, $fy, $fw, $fh)
    $frame.Invalidate()
    if (-not $frame.Visible) { $frame.ShowPassive() }
}

$frame.Add_Paint({
    param($s, $e)
    if ($null -eq $script:rect) { return }
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $r = $script:rect
    $pad = $script:frameTopPad
    $m = $FRAME_MARGIN
    $pen = New-Object System.Drawing.Pen($GREEN, 3)
    $penBrush = New-Object System.Drawing.SolidBrush($GREEN)
    $whiteBrush = New-Object System.Drawing.SolidBrush($WHITE)
    # border
    $g.DrawRectangle($pen, $m, $pad, $r.W, $r.H)
    # 8 handles (corners + edge midpoints)
    $hx = @($m, $m + [int]($r.W / 2), $m + $r.W)
    $hy = @($pad, $pad + [int]($r.H / 2), $pad + $r.H)
    foreach ($yy in $hy) {
        foreach ($xx in $hx) {
            $g.FillRectangle($whiteBrush, $xx - 3, $yy - 3, 7, 7)
            $g.DrawRectangle($pen, $xx - 3, $yy - 3, 7, 7)
        }
    }
    $pen.Dispose(); $penBrush.Dispose(); $whiteBrush.Dispose()
})

function Confirm-Capture {
    $ov.Hide()
    $frame.Hide()
    $r = $script:rect
    if ($null -ne $r -and $r.W -ge $MIN_W -and $r.H -ge $MIN_H) {
        $bmp = New-Object System.Drawing.Bitmap([int]$r.W, [int]$r.H)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($vs.Left + [int]$r.X, $vs.Top + [int]$r.Y, 0, 0, (New-Object System.Drawing.Size([int]$r.W, [int]$r.H)))
        $g.Dispose()
        $script:result = Save-And-Emit $bmp
        $bmp.Dispose()
        $script:captured = $true
    }
    $ov.Close()
}

# ---------------- veil events ----------------
$ov.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $px = [int]$e.X; $py = [int]$e.Y
    if ($script:mode -eq 'adjust') {
        $zone = Hit-Zone $px $py $script:rect
        if ($zone -eq 'move') {
            $script:mode = 'moving'
            $script:dragBase = New-Object System.Drawing.Point($px, $py)
            $script:dragRect = Copy-Rect $script:rect
            $ov.Cursor = [System.Windows.Forms.Cursors]::SizeAll
        }
        elseif ($zone -ne 'none') {
            $script:mode = 'resizing'
            $script:dragEdge = $zone
            $script:dragBase = New-Object System.Drawing.Point($px, $py)
            $script:dragRect = Copy-Rect $script:rect
        }
        else {
            # click outside the frame: start a fresh selection
            $script:mode = 'drawing'
            $script:rect = $null
            $script:selStart = New-Object System.Drawing.Point($px, $py)
            $script:selCur = $script:selStart
            Update-Frame
        }
        return
    }
    # none: start drawing
    $script:mode = 'drawing'
    $script:rect = $null
    $script:selStart = New-Object System.Drawing.Point($px, $py)
    $script:selCur = $script:selStart
    Update-Frame
})
$ov.Add_MouseMove({
    param($s, $e)
    $px = [int]$e.X; $py = [int]$e.Y
    if ($script:mode -eq 'drawing') {
        $script:selCur = New-Object System.Drawing.Point($px, $py)
        $x = [Math]::Min($script:selStart.X, $script:selCur.X)
        $y = [Math]::Min($script:selStart.Y, $script:selCur.Y)
        $w = [Math]::Abs($script:selCur.X - $script:selStart.X)
        $h = [Math]::Abs($script:selCur.Y - $script:selStart.Y)
        $script:rect = Clamp-Rect (New-Rect $x $y $w $h) $maxW $maxH
        Update-Frame
        return
    }
    if ($script:mode -eq 'moving') {
        $dx = $px - $script:dragBase.X
        $dy = $py - $script:dragBase.Y
        $script:rect = Apply-Move $script:dragRect $dx $dy $maxW $maxH
        Update-Frame
        return
    }
    if ($script:mode -eq 'resizing') {
        $dx = $px - $script:dragBase.X
        $dy = $py - $script:dragBase.Y
        $script:rect = Apply-Resize $script:dragRect $script:dragEdge $dx $dy $maxW $maxH
        Update-Frame
        return
    }
    if ($script:mode -eq 'adjust' -and $null -ne $script:rect) {
        $zone = Hit-Zone $px $py $script:rect
        switch ($zone) {
            'move'  { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeAll }
            'N'     { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeNS }
            'S'     { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeNS }
            'E'     { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeWE }
            'W'     { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeWE }
            'NE'    { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
            'SW'    { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeNESW }
            'NW'    { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
            'SE'    { $ov.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE }
            default { $ov.Cursor = [System.Windows.Forms.Cursors]::Default }
        }
    }
})
$ov.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:mode -eq 'drawing') {
        if ($null -ne $script:rect -and $script:rect.W -ge 4 -and $script:rect.H -ge 4) {
            $script:rect = Clamp-Rect $script:rect $maxW $maxH
            $script:mode = 'adjust'
        }
        else {
            $script:rect = $null
            $script:mode = 'none'
        }
        $script:selStart = $null; $script:selCur = $null
        Update-Frame
        # Make sure keyboard focus is back on the veil so Enter/Esc work right away.
        $ov.Activate()
        return
    }
    if ($script:mode -eq 'moving' -or $script:mode -eq 'resizing') {
        $script:mode = 'adjust'
        $script:dragBase = $null; $script:dragRect = $null; $script:dragEdge = $null
        $ov.Activate()
        return
    }
})
$ov.Add_MouseDoubleClick({
    param($s, $e)
    if ($script:mode -eq 'adjust' -and $null -ne $script:rect) {
        $zone = Hit-Zone ([int]$e.X) ([int]$e.Y) $script:rect
        if ($zone -ne 'none') { Confirm-Capture }
    }
})
$ov.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:selStart = $null; $script:selCur = $null
        $ov.Close()
    }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $script:rect) {
        Confirm-Capture
    }
})

# ---------------- demo mode: show a preset rect for visual inspection ----------------
if ($DemoRect -ne '') {
    $parts = $DemoRect -split ','
    if ($parts.Count -ge 4) {
        $script:rect = New-Rect ([int]$parts[0]) ([int]$parts[1]) ([int]$parts[2]) ([int]$parts[3])
        $script:mode = 'adjust'
        $demoTimer = New-Object System.Windows.Forms.Timer
        $demoTimer.Interval = 3000
        $demoTimer.Add_Tick({ $demoTimer.Stop(); $ov.Close() })
        $demoTimer.Start()
    }
}

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
