$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'backend'
$frontendDir = Join-Path $repoRoot 'frontend'
$envFile = Join-Path $backendDir '.env'

if (-not (Test-Path $envFile)) {
    Write-Error "Missing $envFile. Configure backend/.env before starting local dev."
    exit 1
}

$envValues = @{}
foreach ($line in Get-Content $envFile) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
    $idx = $trimmed.IndexOf('=')
    if ($idx -lt 1) { continue }
    $key = $trimmed.Substring(0, $idx).Trim()
    $val = $trimmed.Substring($idx + 1).Trim()
    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
        if ($val.Length -ge 2) {
            $val = $val.Substring(1, $val.Length - 2)
        }
    }
    $envValues[$key] = $val
}

$supabaseUrl = ($envValues['SUPABASE_URL'] | Out-String).Trim()
$supabaseAnonKey = ($envValues['SUPABASE_ANON_KEY'] | Out-String).Trim()

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    Write-Error "SUPABASE_URL or SUPABASE_ANON_KEY is missing in $envFile."
    exit 1
}

if ($supabaseUrl.ToLowerInvariant().Contains('fommrwxpqzkcktweosgp')) {
    Write-Error "Refusing to write production Supabase URL ($supabaseUrl) into local debug dart-defines."
    exit 1
}

$dartToolDir = Join-Path $frontendDir '.dart_tool'
if (-not (Test-Path $dartToolDir)) {
    New-Item -ItemType Directory -Path $dartToolDir -Force | Out-Null
}

$definesPath = Join-Path $dartToolDir 'dev_dart_defines.json'
$definesJson = ([ordered]@{
    TEST_API_URL           = 'http://localhost:5000/api/v1'
    TEST_SUPABASE_URL      = $supabaseUrl
    TEST_SUPABASE_ANON_KEY = $supabaseAnonKey
} | ConvertTo-Json -Depth 2)
[System.IO.File]::WriteAllText($definesPath, $definesJson + "`n", [System.Text.UTF8Encoding]::new($false))

function Test-BackendHealth {
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:5000/health' -TimeoutSec 8 -UseBasicParsing
        return ($resp.StatusCode -eq 200)
    } catch {
        return $false
    }
}

if (Test-BackendHealth) {
    Write-Host 'Local OTP backend already running on http://localhost:5000'
    exit 0
}

$stdoutLog = Join-Path $backendDir 'local_backend.log'
$stderrLog = Join-Path $backendDir 'local_backend.err.log'

Write-Host 'Starting local OTP backend on http://localhost:5000 ...'
Start-Process -FilePath 'node' `
    -ArgumentList 'src/server.js' `
    -WorkingDirectory $backendDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog | Out-Null

$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    if (Test-BackendHealth) {
        Write-Host 'Local OTP backend is healthy on http://localhost:5000'
        exit 0
    }
}

Write-Host 'Failed to start local OTP backend within 20 seconds.'
if (Test-Path $stderrLog) {
    Write-Host '--- local_backend.err.log (last 20 lines) ---'
    Get-Content $stderrLog -Tail 20
}
if (Test-Path $stdoutLog) {
    Write-Host '--- local_backend.log (last 20 lines) ---'
    Get-Content $stdoutLog -Tail 20
}
exit 1
