@echo off
cd /d "C:\Users\ACER\Claude\Projects\matrimony\jothida_matrimony"
git add .
git status
git commit -m "feat: fix Cloudinary upload, fix astrologer onboarding, add logo branding

- fix(cloudinary): call finalize() before copying headers so Content-Type
  multipart/form-data is present in every upload request (was HTTP 400)
- fix(astrologer): replace AstrologerOnboardingScreen with AstrologerRegisterScreen;
  router no longer re-asks for email/password after Google Sign-In
- feat(branding): add app_logo.png to splash, auth screens, and home AppBar
- feat(android): add brand maroon splash background + flutter_launcher_icons config
- chore(env): add Cloudinary API Key / Secret / preset to .env (git-ignored)"
git push
echo.
echo === Done. Press any key to close ===
pause
