@echo off
echo ===================================================
echo   Starting DentaGuru Mobile/Web App (Instant Load)
echo ===================================================
echo.
cd /d "%~dp0frontend"

if not exist "build\web\index.html" (
    echo Building instant web bundle...
    call flutter build web
)

echo Launching instant web server on port 8080...
start "" "http://localhost:8080"
python -m http.server 8080 --directory build/web
