# Chay Flask backend (cong 5000) + Flutter Web (cong 60886) cung luc.
$root = $PSScriptRoot
$py = Join-Path $root "venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "Khong thay venv. Tao bang: python -m venv venv; .\venv\Scripts\pip install -r backend\requirements.txt" -ForegroundColor Yellow
    exit 1
}
Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$root'; & '$py' backend/app.py"
Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$root\mobile'; flutter run -d chrome --web-port 60886"

