Write-Host "Startar Promptbanken lokalt..."

# === Backend ===
Write-Host "Startar backend..."

cd backend

if (!(Test-Path ".venv")) {
    Write-Host "Skapar virtual environment..."
    python -m venv .venv
}

.\.venv\Scripts\Activate.ps1

pip install -r requirements.txt

# Admin env
if (-not $env:ADMIN_PANEL_TOKEN) {
    $env:ADMIN_PANEL_TOKEN=(python -c "import secrets; print(secrets.token_urlsafe(32))")
    Write-Host "ADMIN_PANEL_TOKEN saknades och skapades temporärt för denna session."
}
$env:PROVIDER_ENCRYPTION_KEY=(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

Start-Process powershell -ArgumentList "cd backend; .\.venv\Scripts\Activate.ps1; uvicorn app.main:app --reload --port 8001"

cd ..

# === Frontend ===
Write-Host "Startar frontend..."

Start-Process powershell -ArgumentList "python -m http.server 8000"

Write-Host ""
Write-Host "Frontend: http://localhost:8000"
Write-Host "Backend:  http://localhost:8001/docs"
Write-Host ""
Write-Host "Adminpanelen finns i frontend UI."
