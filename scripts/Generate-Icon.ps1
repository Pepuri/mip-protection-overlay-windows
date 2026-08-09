[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\assets\Protected.ico'),
    [ValidateRange(0.35, 0.75)]
    [double]$BadgeScale = 0.62
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$images = [System.Collections.Generic.List[byte[]]]::new()

foreach ($size in $sizes) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

        # Keep the visible badge close to the size of a conventional Explorer
        # status overlay instead of filling the complete overlay canvas.
        $margin = [Math]::Max(1, [int][Math]::Round($size * 0.02))
        $badgeSize = [Math]::Max(6, [int][Math]::Round($size * $BadgeScale))
        $diameter = [Math]::Max(2, [int][Math]::Round($badgeSize * 0.22))
        $rect = [System.Drawing.RectangleF]::new(
            $margin,
            $size - $badgeSize - $margin,
            $badgeSize,
            $badgeSize
        )

        $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
        try {
            $path.AddArc($rect.Left, $rect.Top, $diameter, $diameter, 180, 90)
            $path.AddArc($rect.Right - $diameter, $rect.Top, $diameter, $diameter, 270, 90)
            $path.AddArc($rect.Right - $diameter, $rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
            $path.AddArc($rect.Left, $rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
            $path.CloseFigure()

            $red = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 210, 20, 30))
            try { $graphics.FillPath($red, $path) } finally { $red.Dispose() }
        }
        finally {
            $path.Dispose()
        }

        # The earlier 28.5% text scale became difficult to read after Explorer
        # reduced the overlay to its final display size. Keep the badge compact,
        # but use heavier and larger lettering with a subtle contrast shadow.
        $fontSize = [Math]::Max(3.5, $badgeSize * 0.34)
        $font = [System.Drawing.Font]::new(
            'Arial',
            [single]$fontSize,
            [System.Drawing.FontStyle]::Bold,
            [System.Drawing.GraphicsUnit]::Pixel
        )
        $white = [System.Drawing.Brushes]::White
        $shadow = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb(110, 90, 0, 8)
        )
        $format = [System.Drawing.StringFormat]::new()
        try {
            $format.Alignment = [System.Drawing.StringAlignment]::Center
            $format.LineAlignment = [System.Drawing.StringAlignment]::Center
            $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap

            $shadowOffset = [Math]::Max(0.35, $size * 0.006)
            $shadowRect = [System.Drawing.RectangleF]::new(
                $rect.X + $shadowOffset,
                $rect.Y + $shadowOffset,
                $rect.Width,
                $rect.Height
            )
            $graphics.DrawString('MIP', $font, $shadow, $shadowRect, $format)
            $graphics.DrawString('MIP', $font, $white, $rect, $format)
        }
        finally {
            $shadow.Dispose()
            $format.Dispose()
            $font.Dispose()
        }

        $stream = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            $images.Add($stream.ToArray())
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null

$fileStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
$writer = [System.IO.BinaryWriter]::new($fileStream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    for ($index = 0; $index -lt $images.Count; $index++) {
        $size = $sizes[$index]
        $writer.Write([byte]$(if ($size -eq 256) { 0 } else { $size }))
        $writer.Write([byte]$(if ($size -eq 256) { 0 } else { $size }))
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$images[$index].Length)
        $writer.Write([UInt32]$offset)
        $offset += $images[$index].Length
    }

    foreach ($image in $images) {
        $writer.Write($image)
    }
}
finally {
    $writer.Dispose()
    $fileStream.Dispose()
}

Write-Host "Generated icon: $OutputPath"
