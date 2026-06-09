# Push jothida_matrimony to GitHub
# Run as: powershell -ExecutionPolicy Bypass -File .\push_to_github.ps1

$ErrorActionPreference = "Stop"
$projectDir = $PSScriptRoot

Set-Location $projectDir

# Configure git identity
git config user.email "sivabeast123123@gmail.com"
git config user.name "sivabeast"

# Init git if needed
if (-not (Test-Path ".git")) {
    git init
    Write-Host "Git initialized"
}

# Set remote
$remoteExists = git remote | Where-Object { $_ -eq "origin" }
if (-not $remoteExists) {
    git remote add origin https://github.com/sivabeast/jothida_matrimony.git
    Write-Host "Remote added"
} else {
    git remote set-url origin https://github.com/sivabeast/jothida_matrimony.git
    Write-Host "Remote updated"
}

# Create assets directories if missing
New-Item -ItemType Directory -Force -Path "assets/images" | Out-Null
New-Item -ItemType Directory -Force -Path "assets/icons" | Out-Null
New-Item -ItemType Directory -Force -Path "assets/fonts" | Out-Null

# Create placeholder files so dirs are tracked
if (-not (Test-Path "assets/images/.gitkeep")) { "" | Out-File -FilePath "assets/images/.gitkeep" -Encoding ASCII }
if (-not (Test-Path "assets/icons/.gitkeep")) { "" | Out-File -FilePath "assets/icons/.gitkeep" -Encoding ASCII }
if (-not (Test-Path "assets/fonts/.gitkeep")) { "" | Out-File -FilePath "assets/fonts/.gitkeep" -Encoding ASCII }

# Create android/app/google-services.json placeholder
New-Item -ItemType Directory -Force -Path "android/app" | Out-Null
if (-not (Test-Path "android/app/google-services.json")) {
@'
{
  "project_info": {
    "project_number": "YOUR_PROJECT_NUMBER",
    "project_id": "YOUR_PROJECT_ID",
    "storage_bucket": "YOUR_PROJECT_ID.appspot.com"
  },
  "client": []
}
'@ | Out-File -FilePath "android/app/google-services.json" -Encoding ASCII
}

# Stage everything
git add -A

# Commit
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
git commit -m "feat: complete Jothida Matrimony app - 65 files - $timestamp" 2>&1 | Out-String | Write-Host

# Push
Write-Host "Pushing to GitHub..."
git push -u origin main 2>&1 | Out-String | Write-Host
Write-Host "Done!"
