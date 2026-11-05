Add-Type -AssemblyName System.Drawing

# Paths to PNG images (16, 32, 48)
$pngFiles = @(
    "frontend/web/icons/gs_favicon_16.png",
    "frontend/web/icons/gs_favicon_32.png",
    "frontend/web/icons/gs_favicon_48.png"
)
$outPath = "frontend/web/icons/gs_favicon.ico"

# Prepare list to hold entry info
$entries = @()
$offset = 6 + (16 * $pngFiles.Count)  # header (6) + directory entries

foreach ($pngPath in $pngFiles) {
    $data = [System.IO.File]::ReadAllBytes($pngPath)
    $size = $data.Length
    $img = [System.Drawing.Image]::FromFile($pngPath)
    $w = $img.Width
    $h = $img.Height
    $img.Dispose()
    $entry = [pscustomobject]@{
        Width  = if ($w -eq 256) {0} else {$w}
        Height = if ($h -eq 256) {0} else {$h}
        ColorCount = 0
        Reserved   = 0
        Planes = 0
        BitCount = 0
        Size = $size
        Offset = $offset
        Data = $data
    }
    $entries += $entry
    $offset += $size
}

# Build binary content
$bytes = New-Object System.Collections.Generic.List[byte]
# Header
$bytes.AddRange([byte[]](0,0))            # Reserved
$bytes.AddRange([byte[]](1,0))            # Type = 1 (icon)
$bytes.AddRange([byte[]]([BitConverter]::GetBytes([ushort]$pngFiles.Count)))

# Directory entries (16 bytes each)
foreach ($e in $entries) {
    $bytes.Add([byte]$e.Width)
    $bytes.Add([byte]$e.Height)
    $bytes.Add([byte]$e.ColorCount)
    $bytes.Add([byte]$e.Reserved)
    $bytes.AddRange([byte[]]([BitConverter]::GetBytes([ushort]$e.Planes)))
    $bytes.AddRange([byte[]]([BitConverter]::GetBytes([ushort]$e.BitCount)))
    $bytes.AddRange([byte[]]([BitConverter]::GetBytes([uint]$e.Size)))
    $bytes.AddRange([byte[]]([BitConverter]::GetBytes([uint]$e.Offset)))
}

# Image data blocks
foreach ($e in $entries) {
    $bytes.AddRange($e.Data)
}

# Write the .ico file
[System.IO.File]::WriteAllBytes($outPath, $bytes.ToArray())
Write-Host "ICO generated at $outPath"

