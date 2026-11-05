Add-Type -AssemblyName System.Drawing
$icoPath = "frontend/web/icons/gs_favicon.ico"
$bytes = [System.IO.File]::ReadAllBytes($icoPath)
# Header
$reserved = [BitConverter]::ToUInt16($bytes,0)
$type = [BitConverter]::ToUInt16($bytes,2)
$count = [BitConverter]::ToUInt16($bytes,4)
Write-Host "Icon count: $count"
for ($i=0; $i -lt $count; $i++) {
    $off = 6 + $i*16
    $width = $bytes[$off]
    $height = $bytes[$off+1]
    $colorCount = $bytes[$off+2]
    $reserved2 = $bytes[$off+3]
    $planes = [BitConverter]::ToUInt16($bytes,$off+4)
    $bitCount = [BitConverter]::ToUInt16($bytes,$off+6)
    $size = [BitConverter]::ToUInt32($bytes,$off+8)
    $offset = [BitConverter]::ToUInt32($bytes,$off+12)
    $w = if ($width -eq 0) {256} else {$width}
    $h = if ($height -eq 0) {256} else {$height}
    Write-Host ("Entry {0}: {1}x{2}, Size={3} bytes, Offset={4}" -f $i, $w, $h, $size, $offset)
}
