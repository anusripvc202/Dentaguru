param(
    [string]$StagingOtpAccessKey = '',
    [switch]$Clean,
    [switch]$AllowNonStagingBranch
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'backend'
$frontendDir = Join-Path $repoRoot 'frontend'
$envFile = Join-Path $backendDir '.env'

# 1. Verify current Git branch is 'staging' so we never accidentally build staging APK from 'main'
Push-Location $repoRoot
try {
    $currentBranch = (git branch --show-current | Out-String).Trim()
    if (-not $AllowNonStagingBranch -and $currentBranch -ne 'staging') {
        Write-Error "ABORT: Current Git branch is '$currentBranch'. Switch to 'staging' (git checkout staging) before building the Staging APK, or pass -AllowNonStagingBranch."
        exit 1
    }
    Write-Host "Git branch verified: $currentBranch"
} finally {
    Pop-Location
}

# 2. Read staging Supabase credentials (and optional STAGING_OTP_ACCESS_KEY) from gitignored backend/.env
if (-not (Test-Path $envFile)) {
    Write-Error "Missing $envFile. Configure staging SUPABASE_URL, SUPABASE_ANON_KEY, and STAGING_OTP_ACCESS_KEY in backend/.env."
    exit 1
}

$envValues = @{}
foreach ($line in Get-Content $envFile) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $idx = $trimmed.IndexOf('=')
    if ($idx -lt 1) { continue }
    $k = $trimmed.Substring(0, $idx).Trim()
    $v = $trimmed.Substring($idx + 1).Trim()
    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
        if ($v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
    }
    $envValues[$k] = $v
}

$supabaseUrl = ($envValues['SUPABASE_URL'] | Out-String).Trim()
$supabaseAnonKey = ($envValues['SUPABASE_ANON_KEY'] | Out-String).Trim()

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    Write-Error "SUPABASE_URL or SUPABASE_ANON_KEY is missing in $envFile."
    exit 1
}

if (-not $supabaseUrl.ToLowerInvariant().Contains('ojinzcdldwugpnxrnjcq') -or $supabaseUrl.ToLowerInvariant().Contains('fommrwxpqzkcktweosgp')) {
    Write-Error "ABORT: backend/.env SUPABASE_URL ($supabaseUrl) is NOT the staging project (ojinzcdldwugpnxrnjcq)."
    exit 1
}

$resolvedOtpKey = $StagingOtpAccessKey.Trim()
if (-not $resolvedOtpKey -and $env:STAGING_OTP_ACCESS_KEY) {
    $resolvedOtpKey = $env:STAGING_OTP_ACCESS_KEY.Trim()
}
if (-not $resolvedOtpKey -and $envValues.ContainsKey('STAGING_OTP_ACCESS_KEY')) {
    $resolvedOtpKey = ($envValues['STAGING_OTP_ACCESS_KEY'] | Out-String).Trim()
}

if ([string]::IsNullOrWhiteSpace($resolvedOtpKey)) {
    Write-Warning "STAGING_OTP_ACCESS_KEY is NOT set in backend/.env or environment. Live Render Staging (dentaguru-backend-test.onrender.com) will return HTTP 403 (STAGING_OTP_KEY_REQUIRED) for OTP login until you add STAGING_OTP_ACCESS_KEY=<render-staging-key> to backend/.env or pass -StagingOtpAccessKey."
} else {
    Write-Host "STAGING_OTP_ACCESS_KEY detected (value redacted)."
}

# 3. Prepare Flutter dependencies & write UTF-8 (no BOM) staging_dart_defines.json
Push-Location $frontendDir
try {
    if ($Clean) {
        flutter clean
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $dartToolDir = Join-Path $frontendDir '.dart_tool'
    if (-not (Test-Path $dartToolDir)) {
        New-Item -ItemType Directory -Path $dartToolDir -Force | Out-Null
    }

    $defines = [ordered]@{
        TEST_API_URL           = 'https://dentaguru-backend-test.onrender.com/api/v1'
        TEST_SUPABASE_URL      = $supabaseUrl
        TEST_SUPABASE_ANON_KEY = $supabaseAnonKey
        OTP_TEST_DISPLAY       = 'true'
    }
    if (-not [string]::IsNullOrWhiteSpace($resolvedOtpKey)) {
        $defines['STAGING_OTP_ACCESS_KEY'] = $resolvedOtpKey
    }

    $definesPath = Join-Path $dartToolDir 'staging_dart_defines.json'
    $definesJson = ($defines | ConvertTo-Json -Depth 2)
    [System.IO.File]::WriteAllText($definesPath, $definesJson + "`n", [System.Text.UTF8Encoding]::new($false))

    # 4. Build dedicated Android staging flavor APK
    flutter build apk --flavor staging --release --dart-define-from-file=.dart_tool/staging_dart_defines.json
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    # 5. Binary-verify compiled libapp.so enforces strict staging isolation
    $apkPath = Join-Path $frontendDir 'build\app\outputs\flutter-apk\app-staging-release.apk'
    if (-not (Test-Path $apkPath)) {
        Write-Error "Expected APK not found at $apkPath"
        exit 1
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
    try {
        $entry = $zip.GetEntry('lib/arm64-v8a/libapp.so')
        $ms = New-Object System.IO.MemoryStream
        $stream = $entry.Open()
        $stream.CopyTo($ms)
        $stream.Close()
        $text = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())
        $ms.Close()

        $hasStagingApi = $text.Contains('dentaguru-backend-test.onrender.com')
        $hasStagingSupa = $text.Contains('ojinzcdldwugpnxrnjcq')
        $hasProdApi = $text.Contains('dentaguru-backend.onrender.com')
        $hasProdSupa = $text.Contains('fommrwxpqzkcktweosgp')

        Write-Host "=== STAGING APK BINARY VERIFICATION ==="
        Write-Host "APK: $apkPath"
        Write-Host "HAS_STAGING_BACKEND: $hasStagingApi"
        Write-Host "HAS_STAGING_SUPABASE: $hasStagingSupa"
        Write-Host "HAS_PROD_BACKEND: $hasProdApi"
        Write-Host "HAS_PROD_SUPABASE: $hasProdSupa"

        if (-not $hasStagingApi -or -not $hasStagingSupa -or $hasProdApi -or $hasProdSupa) {
            Write-Error "BINARY ISOLATION CHECK FAILED! Do not distribute this APK."
            exit 1
        }
    } finally {
        $zip.Dispose()
    }

    $hash = (Get-FileHash -Algorithm SHA256 $apkPath).Hash
    Write-Host "APK_SHA256: $hash"
    Write-Host "Staging APK ready: $apkPath"
} finally {
    Pop-Location
}
