Add-Type -AssemblyName System.Drawing

$source = "frontend/web/icons/gs_health_favicon.png"
$output = "frontend/web/icons/gs_favicon_32.png"
$size = 32

$image = [System.Drawing.Image]::FromFile($source)
$bitmap = New-Object System.Drawing.Bitmap($size, $size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

$ratio = [Math]::Min($size / $image.Width, $size / $image.Height)
$width = [int]($image.Width * $ratio)
$height = [int]($image.Height * $ratio)

$x = [int](($size - $width) / 2)
$y = [int](($size - $height) / 2)

$graphics.DrawImage($image, $x, $y, $width, $height)
$bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$bitmap.Dispose()
$image.Dispose()

Write-Host "32x32 favicon generation completed."

