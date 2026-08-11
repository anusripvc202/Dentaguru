# PowerShell Script for Local Firebase App Distribution
# Usage: .\scripts\distribute_app.ps1 -AppId "1:1234567890:android:abcdef" -TesterGroup "internal-testers"

param (
    [string]$AppId = $env:FIREBASE_APP_ID_ANDROID,
    [string]$TesterGroup = "internal-testers",
    [string]$ReleaseNotes = "Local build distribution via DentaGuru CLI"
)

$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting DentaGuru Firebase App Distribution Pipeline..." -ForegroundColor Cyan

# 1. Verify Firebase CLI
if (-not (Get-Command "firebase" -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Firebase CLI is not installed. Please install via: npm install -g firebase-tools" -ForegroundColor Red
    exit 1
}

# 2. Build Flutter APK
Write-Host "📦 Building Flutter Release APK..." -ForegroundColor Yellow
Set-Location "$PSScriptRoot\..\frontend"
flutter build apk --release

$ApkPath = "$PSScriptRoot\..\frontend\build\app\outputs\flutter-apk\app-release.apk"

if (-not (Test-Path $ApkPath)) {
    Write-Host "❌ APK build failed. Output file not found at: $ApkPath" -ForegroundColor Red
    exit 1
}

if (-not $AppId) {
    Write-Host "⚠️ FIREBASE_APP_ID_ANDROID environment variable is missing." -ForegroundColor Yellow
    $AppId = Read-Host "Enter your Firebase Android App ID (e.g., 1:123456:android:abc)"
}

# 3. Distribute to Firebase
Write-Host "📲 Distributing APK to Firebase App Distribution..." -ForegroundColor Green
firebase appdistribution:distribute $ApkPath --app $AppId --groups $TesterGroup --release-notes $ReleaseNotes

Write-Host "✅ Firebase App Distribution completed successfully!" -ForegroundColor Green
