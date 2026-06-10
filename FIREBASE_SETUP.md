# Firebase Setup — Jothida Matrimony

The app code now has a complete, production-ready authentication flow. However,
**authentication cannot work until the real Firebase project config replaces the
placeholders in this repo.** The errors you saw prove this:

| Error on screen | Real cause |
|---|---|
| `[firebase_auth/unknown] … API key not valid` | `lib/firebase_options.dart` + `android/app/google-services.json` contain **fake placeholder values** (`AIzaSyA000…`, `"client": []`). |
| `sign_in_failed … :10:` (ApiException 10 / DEVELOPER_ERROR) | The app's **SHA-1 fingerprint and OAuth client are not registered** in Firebase. |
| "Please select an email address" on the Google provider | The Google provider's **support email is not configured**. |

Do the steps below once and all three disappear.

---

## 1. Firebase project + Android app

1. Open the [Firebase Console](https://console.firebase.google.com) → use your
   existing project (`matrimony-app-bd0d5`) or create one.
2. Add an **Android app** with this exact package name:

   ```
   com.jothida.jothida_matrimony
   ```

   (CI generates the Android project with `--org=com.jothida
   --project-name=jothida_matrimony`, so the applicationId is the above. If you
   build locally, confirm `android/app/build.gradle` → `applicationId` matches.)

## 2. Register the SHA-1 / SHA-256 fingerprints (fixes error 10) — IMPORTANT

**This is the root cause of "after selecting a Google account, login fails."**

Google Sign-In returns a null ID token (→ ApiException 10 / DEVELOPER_ERROR)
because the signing certificate's SHA-1 is not registered in Firebase. Worse,
CI used to regenerate a *random* debug keystore on every build, so the SHA-1
changed every run and could never be registered.

**This is now fixed in the repo:** a fixed, shared debug keystore is committed at
`ci/debug.keystore` and CI copies it to `~/.android/debug.keystore` before every
build (see `.github/workflows/ci.yml`). Both the debug and release APKs are
signed with it, so the SHA-1 is now **stable**. Register these exact
fingerprints once:

```
SHA-1:   8B:4E:88:65:BD:95:8B:9B:46:60:32:B4:C8:D7:32:4D:87:7B:AD:BE
SHA-256: BE:11:8D:5D:BE:46:60:17:09:E1:11:F2:41:4C:B1:17:64:6F:A1:E4:04:1F:F1:C8:D0:21:09:E4:97:B0:DD:FE
```

In Firebase Console → **Project settings → Your apps → Android app
(`com.jothida.jothida_matrimony`) → Add fingerprint**, paste **both** values,
then **re-download `google-services.json`** (step 3) and update the
`GOOGLE_SERVICES_JSON` CI secret with the new contents.

> If you build **locally** instead of using the committed keystore, get your own
> machine's fingerprint with the commands below and register that one too. You
> can register multiple SHA-1s on the same app.

```bash
cd android
./gradlew signingReport
# or:
keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
```

Copy the `SHA1` (and `SHA-256`) values. In Firebase Console →
**Project settings → Your apps → Android app → Add fingerprint**, paste them.
Add the **release** keystore fingerprint too before you publish.

## 3. Download the real `google-services.json`

Firebase Console → Project settings → Your apps → Android → **Download
`google-services.json`** and place it at:

```
android/app/google-services.json
```

This file must contain a non-empty `oauth_client` array and a
`default_web_client_id` — that is what lets `google_sign_in` return an ID token.

## 4. Regenerate `lib/firebase_options.dart`

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Select the same project and Android app. This overwrites the placeholder
`firebase_options.dart` with real keys (fixing "API key not valid").

## 5. Enable sign-in providers

Firebase Console → **Authentication → Sign-in method**, enable:

- **Google** — and **select a Support email** (this is the red error in your
  screenshot; the provider stays disabled until you do).
- **Email/Password**
- **Phone** (the app also supports OTP login)

## 6. Firestore database + rules

1. Console → **Firestore Database → Create database** (production mode).
2. Deploy the rules in `firestore.rules` (a user can only read/write their own
   `users/{uid}` document; admins/astrologers can read for moderation):

   ```bash
   npm install -g firebase-tools
   firebase login
   firebase deploy --only firestore:rules
   ```

## 7. CI/CD secrets (GitHub Actions)

`.github/workflows/ci.yml` already reads these — add them in
**Repo → Settings → Secrets and variables → Actions**:

- `GOOGLE_SERVICES_JSON` — full contents of the real `google-services.json`
- `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`
- `RAZORPAY_KEY_ID`

---

## What the code stores on login

On a successful Google (or email/phone) sign-in, `users/{uid}` is created once
with these fields and **never duplicated**; returning users only get
`lastLoginAt` refreshed:

| Field | Source |
|---|---|
| `uid` | Firebase Auth (document id) |
| `displayName` (name) | Google account |
| `email` | Google account |
| `photoUrl` | Google account |
| `createdAt` | server timestamp, first login only |
| `lastLoginAt` | server timestamp, every login |
| `isProfileComplete` (profileCompleted) | `false` for new users |
| `membershipType` | `free` for new users |

> Note on naming: the app's existing schema uses `displayName` and
> `isProfileComplete`; these are the same concepts as the requested `name` and
> `profileCompleted`. They were kept to avoid breaking the other 60+ screens.

---

## Testing the flow

1. Complete steps 1–6 above.
2. `flutter clean && flutter pub get`
3. `flutter run` on a real device or emulator **with Google Play services**.
4. Tap **Continue with Google** → choose an account → you should land on Home.
5. In Firebase Console → Authentication → Users, confirm the new user appears.
6. In Firestore → `users` → confirm the document with the fields above.
7. Sign in again with the same account → confirm **no duplicate** doc and that
   `lastLoginAt` changed.
8. Tap **Sign Out** (My Profile tab) → you should return to Login.
9. Error cases to verify: turn off Wi-Fi (network message), dismiss the Google
   sheet (no error shown), wrong email password (friendly message).
