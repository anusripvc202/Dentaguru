Add-Type -AssemblyName System.Drawing
$path = "frontend/web/icons/gs_favicon_32.png"
$img = [System.Drawing.Image]::FromFile($path)
Write-Output "Width=$($img.Width) Height=$($img.Height)"
$img.Dispose()
