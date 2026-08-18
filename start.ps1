# Starts all three services in separate windows.
$root = $PSScriptRoot

Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$root\backend'; npm run dev"
Start-Sleep -Seconds 2
Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$root\ai-service'; py -m uvicorn app.main:app --reload --port 8000"
Start-Sleep -Seconds 2
Start-Process powershell -ArgumentList "-NoExit","-Command","cd '$root\frontend'; flutter run -d chrome"

Write-Host "All three started in separate windows."