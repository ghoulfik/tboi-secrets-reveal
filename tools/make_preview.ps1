# Regenerates workshop/preview.png - the Steam Workshop thumbnail.
#
# 640x640, well under Steam's 1 MB limit. Scales the marker sheet up with
# nearest-neighbour so the pixel art stays crisp. Tile count is read from the
# sheet width, so adding a marker needs no edit here.
#
# Run:  powershell -ExecutionPolicy Bypass -File tools\make_preview.ps1

Add-Type -AssemblyName System.Drawing

$root    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$markers = Join-Path $root 'resources\gfx\secretsreveal_markers.png'
$outDir  = Join-Path $root 'workshop'
$out     = Join-Path $outDir 'preview.png'

$S = 640
$bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# Background: dark vertical gradient, Isaac-basement charcoal
$bgRect = New-Object System.Drawing.Rectangle 0, 0, $S, $S
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bgRect,
    [System.Drawing.Color]::FromArgb(255, 26, 22, 28),
    [System.Drawing.Color]::FromArgb(255, 12, 10, 14),
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$g.FillRectangle($bgBrush, $bgRect)
$bgBrush.Dispose()

# Faint grid, like a room's tile lattice
$gridPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(16, 255, 255, 255)), 1
for ($x = 0; $x -le $S; $x += 40) {
    $g.DrawLine($gridPen, $x, 0, $x, $S)
    $g.DrawLine($gridPen, 0, $x, $S, $x)
}
$gridPen.Dispose()

# The three markers, scaled 4x, evenly spaced across the middle
$src = [System.Drawing.Image]::FromFile($markers)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

$count = [int]($src.Width / 32)
$scale = 3
$tile  = 32 * $scale          # 96
$gap   = 20
$total = ($count * $tile) + (($count - 1) * $gap)
$startX = [int](($S - $total) / 2)
$y      = 250

# The sheet ships white and is tinted at draw time in game, so the preview has
# to apply the same default colours. Keep in step with DEFAULTS in main.lua.
$tints = @(
    @(0.35, 0.86, 1.00),   # tinted rock          - cyan
    @(1.00, 0.80, 0.24),   # super tinted rock    - gold
    @(0.78, 0.51, 1.00),   # open crawlspace      - violet
    @(0.47, 0.90, 0.55),   # X-marked skull       - green
    @(0.78, 0.51, 1.00)    # buried crawlspace    - violet
)

for ($i = 0; $i -lt $count; $i++) {
    $dst = New-Object System.Drawing.Rectangle (($startX + $i * ($tile + $gap))), $y, $tile, $tile

    $t = @(1.0, 1.0, 1.0)
    if ($i -lt $tints.Count) { $t = $tints[$i] }

    $cm = New-Object System.Drawing.Imaging.ColorMatrix
    $cm.Matrix00 = $t[0]; $cm.Matrix11 = $t[1]; $cm.Matrix22 = $t[2]
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetColorMatrix($cm)

    $g.DrawImage($src, $dst, ($i * 32), 0, 32, 32, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $attr.Dispose()
}
$src.Dispose()

# Title
$titleFont = New-Object System.Drawing.Font 'Segoe UI', 58, ([System.Drawing.FontStyle]::Bold)
$subFont   = New-Object System.Drawing.Font 'Segoe UI', 23, ([System.Drawing.FontStyle]::Regular)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center

$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 245, 242, 238))
$dim   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 150, 146, 158))
$shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, 0, 0, 0))

# DrawString(text, font, brush, layoutRect, format)
$g.DrawString('SECRETS', $titleFont, $shade, (New-Object System.Drawing.RectangleF 3, 75, $S, 90), $fmt)
$g.DrawString('SECRETS', $titleFont, $white, (New-Object System.Drawing.RectangleF 0, 72, $S, 90), $fmt)
$g.DrawString('REVEAL',  $titleFont, $shade, (New-Object System.Drawing.RectangleF 3, 143, $S, 90), $fmt)
$g.DrawString('REVEAL',  $titleFont, $white, (New-Object System.Drawing.RectangleF 0, 140, $S, 90), $fmt)

# Shrink the subtitle until it fits the width, so editing the wording later
# cannot silently clip it off the edge of the card.
$subtitle = 'Secret rooms  -  Crawlspaces  -  Hidden rocks'
$maxWidth = $S - 60
for ($pt = 23; $pt -ge 12; $pt--) {
    $probe = New-Object System.Drawing.Font 'Segoe UI', $pt, ([System.Drawing.FontStyle]::Regular)
    $w = $g.MeasureString($subtitle, $probe).Width
    $probe.Dispose()
    if ($w -le $maxWidth) { break }
}
$subFont.Dispose()
$subFont = New-Object System.Drawing.Font 'Segoe UI', $pt, ([System.Drawing.FontStyle]::Regular)

$g.DrawString($subtitle, $subFont, $dim,
    (New-Object System.Drawing.RectangleF 0, 424, $S, 40), $fmt)

# Accent rule under the subtitle
$rule = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 90, 220, 255))
$g.FillRectangle($rule, [int](($S - 120) / 2), 478, 120, 3)

foreach ($d in @($titleFont, $subFont, $white, $dim, $shade, $rule, $fmt, $g)) { $d.Dispose() }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$kb = [math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Output "wrote $out ($kb KB)"
