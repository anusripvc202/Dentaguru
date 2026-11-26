param(
    [string]$Device = 'chrome',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'ensure_local_backend.ps1')
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$frontendDir = Join-Path $repoRoot 'frontend'

Push-Location $frontendDir
try {
    & flutter run -d $Device --dart-define-from-file=.dart_tool/dev_dart_defines.json @FlutterArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
