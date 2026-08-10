# Regenerates resources/gfx/secretsreveal_markers.png
#
# 160x32 sheet, five 32x32 markers side by side:
#   0 = Tinted Rock            (diamond)
#   1 = Super Tinted Rock      (four-pointed star)
#   2 = Crawlspace, open       (solid down arrow)
#   3 = X-marked skull         (X)
#   4 = Rock hiding a crawlspace (hollow down arrow)
#
# The sheet is drawn WHITE on a black outline. main.lua tints each marker at
# draw time, so the colour is a user setting rather than baked in here. A tint
# multiplies, so white takes the colour exactly and the black outline survives
# untouched (black x anything = black).
#
# Every glyph is a distinct shape, so two markers set to the same colour are
# still tellable apart.
#
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File tools\make_markers.ps1

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$out  = Join-Path $root 'resources\gfx\secretsreveal_markers.png'

$TILE  = 32
$COUNT = 5

$bmp = New-Object System.Drawing.Bitmap ($TILE * $COUNT), $TILE, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

$shadowColor = [System.Drawing.Color]::FromArgb(210, 0, 0, 0)
$accentColor = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$shadow = New-Object System.Drawing.SolidBrush $shadowColor
$accent = New-Object System.Drawing.SolidBrush $accentColor

function Draw-Brackets {
    param($g, $brush, [int]$ox, [int]$inset, [int]$arm, [int]$th)

    $far    = 32 - $inset - $th
    $farArm = 32 - $inset - $arm

    $g.FillRectangle($brush, ($ox + $inset),  $inset,  $arm, $th)   # top-left
    $g.FillRectangle($brush, ($ox + $inset),  $inset,  $th, $arm)
    $g.FillRectangle($brush, ($ox + $farArm), $inset,  $arm, $th)   # top-right
    $g.FillRectangle($brush, ($ox + $far),    $inset,  $th, $arm)
    $g.FillRectangle($brush, ($ox + $inset),  $far,    $arm, $th)   # bottom-left
    $g.FillRectangle($brush, ($ox + $inset),  $farArm, $th, $arm)
    $g.FillRectangle($brush, ($ox + $farArm), $far,    $arm, $th)   # bottom-right
    $g.FillRectangle($brush, ($ox + $far),    $farArm, $th, $arm)
}

function Draw-Polygon {
    param($g, $brush, [int]$ox, $points)
    $pts = @()
    foreach ($p in $points) { $pts += New-Object System.Drawing.Point (($p[0] + $ox), $p[1]) }
    $g.FillPolygon($brush, [System.Drawing.Point[]]$pts)
}

function Draw-HollowPolygon {
    param($g, [int]$ox, $points, $shadowColor, $accentColor)
    $pts = @()
    foreach ($p in $points) { $pts += New-Object System.Drawing.Point (($p[0] + $ox), $p[1]) }
    $pen1 = New-Object System.Drawing.Pen $shadowColor, 5
    $pen2 = New-Object System.Drawing.Pen $accentColor, 2
    $pen1.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $pen2.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $g.DrawPolygon($pen1, [System.Drawing.Point[]]$pts)
    $g.DrawPolygon($pen2, [System.Drawing.Point[]]$pts)
    $pen1.Dispose(); $pen2.Dispose()
}

for ($i = 0; $i -lt $COUNT; $i++) {
    $ox = $i * $TILE

    # dark outline pass, then the white pass on top
    Draw-Brackets $g $shadow $ox 2 11 5
    Draw-Brackets $g $accent $ox 3  9 3

    switch ($i) {
        0 {
            # diamond
            Draw-Polygon $g $shadow $ox @(@(16,9),@(23,16),@(16,23),@(9,16))
            Draw-Polygon $g $accent $ox @(@(16,11),@(21,16),@(16,21),@(11,16))
        }
        1 {
            # four-pointed star
            Draw-Polygon $g $shadow $ox @(@(16,7),@(18,14),@(25,16),@(18,18),@(16,25),@(14,18),@(7,16),@(14,14))
            Draw-Polygon $g $accent $ox @(@(16,9),@(17,15),@(23,16),@(17,17),@(16,23),@(15,17),@(9,16),@(15,15))
        }
        2 {
            # solid down arrow - a crawlspace that is already open
            Draw-Polygon $g $shadow $ox @(@(9,10),@(23,10),@(16,23))
            Draw-Polygon $g $accent $ox @(@(11,12),@(21,12),@(16,20))
        }
        3 {
            # X - matches the mark on the skull it points at
            $barsShadow = @(
                @(@(9,11),@(11,9),@(23,21),@(21,23)),
                @(@(21,9),@(23,11),@(11,23),@(9,21))
            )
            $barsAccent = @(
                @(@(11,12),@(12,11),@(21,20),@(20,21)),
                @(@(20,11),@(21,12),@(12,21),@(11,20))
            )
            foreach ($b in $barsShadow) { Draw-Polygon $g $shadow $ox $b }
            foreach ($b in $barsAccent) { Draw-Polygon $g $accent $ox $b }
        }
        4 {
            # hollow down arrow - a crawlspace still buried under this rock
            Draw-HollowPolygon $g $ox @(@(10,11),@(22,11),@(16,22)) $shadowColor $accentColor
        }
    }
}

$g.Dispose(); $shadow.Dispose(); $accent.Dispose()

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Output "wrote $out"
