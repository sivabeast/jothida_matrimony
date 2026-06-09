# Step 1: Fix any stale lock files
$gitDir = "$PSScriptRoot\.git"
if (Test-Path "$gitDir\config.lock") { Remove-Item "$gitDir\config.lock" -Force }
if (Test-Path "$gitDir\index.lock") { Remove-Item "$gitDir\index.lock" -Force }
if (Test-Path "$gitDir\HEAD.lock") { Remove-Item "$gitDir\HEAD.lock" -Force }

# Step 2: Recreate .git/config cleanly
[System.IO.File]::WriteAllText("$gitDir\config", @"
[core]
    repositoryformatversion = 0
    filemode = false
    bare = false
    logallrefupdates = true
[remote "origin"]
    url = https://github.com/sivabeast/jothida_matrimony.git
    fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
    remote = origin
    merge = refs/heads/main
[user]
    email = sivabeast123123@gmail.com
    name = sivabeast
"@)

Set-Location $PSScriptRoot

# Step 3: Create missing asset dirs
New-Item -ItemType Directory -Force -Path "assets\images" | Out-Null
New-Item -ItemType Directory -Force -Path "assets\icons" | Out-Null
New-Item -ItemType Directory -Force -Path "assets\fonts" | Out-Null
if (-not (Test-Path "assets\images\.gitkeep")) { "" | Out-File "assets\images\.gitkeep" -Encoding ASCII }
if (-not (Test-Path "assets\icons\.gitkeep"))  { "" | Out-File "assets\icons\.gitkeep"  -Encoding ASCII }
if (-not (Test-Path "assets\fonts\.gitkeep"))  { "" | Out-File "assets\fonts\.gitkeep"  -Encoding ASCII }

# Step 4: Create android/app/google-services.json placeholder (needed by build)
New-Item -ItemType Directory -Force -Path "android\app" | Out-Null
if (-not (Test-Path "android\app\google-services.json")) {
    @'
{
  "project_info": {
    "project_number": "REPLACE_WITH_YOUR_PROJECT_NUMBER",
    "project_id": "REPLACE_WITH_YOUR_PROJECT_ID",
    "storage_bucket": "REPLACE_WITH_YOUR_PROJECT_ID.appspot.com"
  },
  "client": []
}
'@ | Out-File "android\app\google-services.json" -Encoding ASCII
}

# Step 5: Git add & commit
git add -A
git commit -m "feat: complete Jothida Matrimony app - 65 dart files + firestore rules + CI/CD"
git branch -M main

# Step 6: Push
Write-Host ""
Write-Host "=== Pushing to GitHub ==="
git push -u origin main
Write-Host ""
Write-Host "DONE! Check https://github.com/sivabeast/jothida_matrimony"
