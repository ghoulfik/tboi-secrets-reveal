# Regenerates resources/gfx/secretsreveal_markers.png
#
# 128x32 sheet, four 32x32 markers side by side:
#   0 = Tinted Rock (cyan)        1 = Super Tinted Rock (gold)
#   2 = Crawlspace (violet)       3 = Rubble Rock, may hide one (green, hollow)
#
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools\make_markers.ps1

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out  = Join-Path $root 'resources\gfx\secretsreveal_markers.png'

$bmp = New-Object System.Drawing.Bitmap 128, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

$shadowColor = [System.Drawing.Color]::FromArgb(210, 0, 0, 0)
$shadow = New-Object System.Drawing.SolidBrush $shadowColor

# tile index -> accent colour
$colors = @(
    [System.Drawing.Color]::FromArgb(255,  90, 220, 255),  # tinted rock
    [System.Drawing.Color]::FromArgb(255, 255, 205,  60),  # super tinted rock
    [System.Drawing.Color]::FromArgb(255, 200, 130, 255),  # crawlspace
    [System.Drawing.Color]::FromArgb(255, 120, 230, 140)   # rubble rock (candidate)
)

function Draw-Brackets {
    param($g, $brush, [int]$ox, [int]$inset, [int]$arm, [int]$th)

    $far = 32 - $inset - $th
    $farArm = 32 - $inset - $arm

    # top-left
    $g.FillRectangle($brush, ($ox + $inset), $inset, $arm, $th)
    $g.FillRectangle($brush, ($ox + $inset), $inset, $th, $arm)
    # top-right
    $g.FillRectangle($brush, ($ox + $farArm), $inset, $arm, $th)
    $g.FillRectangle($brush, ($ox + $far), $inset, $th, $arm)
    # bottom-left
    $g.FillRectangle($brush, ($ox + $inset), $far, $arm, $th)
    $g.FillRectangle($brush, ($ox + $inset), $farArm, $th, $arm)
    # bottom-right
    $g.FillRectangle($brush, ($ox + $farArm), $far, $arm, $th)
    $g.FillRectangle($brush, ($ox + $far), $farArm, $th, $arm)
}

function Draw-Polygon {
    param($g, $brush, [int]$ox, $points)
    $pts = @()
    foreach ($p in $points) {
        $pts += New-Object System.Drawing.Point (($p[0] + $ox), $p[1])
    }
    $g.FillPolygon($brush, [System.Drawing.Point[]]$pts)
}

for ($i = 0; $i -lt 4; $i++) {
    $ox = $i * 32
    $accent = New-Object System.Drawing.SolidBrush $colors[$i]

    # dark outline pass, then the accent pass on top
    Draw-Brackets $g $shadow $ox 2 11 5
    Draw-Brackets $g $accent $ox 3  9 3

    switch ($i) {
        0 {
            # diamond
            Draw-Polygon $g $shadow  $ox @(@(16,9),@(23,16),@(16,23),@(9,16))
            Draw-Polygon $g $accent  $ox @(@(16,11),@(21,16),@(16,21),@(11,16))
        }
        1 {
            # four-pointed star
            Draw-Polygon $g $shadow $ox @(@(16,7),@(18,14),@(25,16),@(18,18),@(16,25),@(14,18),@(7,16),@(14,14))
            Draw-Polygon $g $accent $ox @(@(16,9),@(17,15),@(23,16),@(17,17),@(16,23),@(15,17),@(9,16),@(15,15))
        }
        2 {
            # downward arrow (into the hole)
            Draw-Polygon $g $shadow $ox @(@(9,10),@(23,10),@(16,23))
            Draw-Polygon $g $accent $ox @(@(11,12),@(21,12),@(16,20))
        }
        3 {
            # hollow version of the crawlspace arrow: "might be one under here"
            $tri = @(
                (New-Object System.Drawing.Point (($ox + 10)), 11),
                (New-Object System.Drawing.Point (($ox + 22)), 11),
                (New-Object System.Drawing.Point (($ox + 16)), 22)
            )
            $penShadow = New-Object System.Drawing.Pen $shadowColor, 5
            $penAccent = New-Object System.Drawing.Pen $colors[$i], 2
            $penShadow.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
            $penAccent.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
            $g.DrawPolygon($penShadow, [System.Drawing.Point[]]$tri)
            $g.DrawPolygon($penAccent, [System.Drawing.Point[]]$tri)
            $penShadow.Dispose()
            $penAccent.Dispose()
        }
    }
    $accent.Dispose()
}

$g.Dispose()
$shadow.Dispose()

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Output "wrote $out"
