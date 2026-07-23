# Firebase Setup — Jothida Matrimony

The app is fully wired for Firebase (Auth, Firestore, Storage, FCM). It currently
runs in **demo mode** (`kBypassAuth = true` in `lib/core/config/dev_config.dart`)
with placeholder Firebase config so the UI works without a backend.
Follow the steps below to connect your real Firebase project, then set
`kBypassAuth = false`.

> Note: errors like `API key not valid`, `sign_in_failed (ApiException 10)`, or
> "Please select an email address" all mean the placeholder config is still in
> place or SHA keys / support email are missing — steps 2–3 fix them.

---

## 1. Create the Firebase project

1. Go to https://console.firebase.google.com → **Add project** → name it
   (e.g. `jothida-matrimony`).
2. In the project, add an **Android app** with package name
   `com.example.jothida_matrimony` (or your real applicationId from
   `android/app/build.gradle`). Add an **iOS app** too if you ship iOS.

## 2. Generate the config files

The easiest way (replaces `lib/firebase_options.dart` and
`android/app/google-services.json` automatically):

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Pick your project and platforms when prompted. That's it — both placeholder
files are overwritten with real values.

## 3. Enable Authentication providers

Firebase Console → **Build → Authentication → Sign-in method**, enable:

| Provider | Notes |
|---|---|
| **Email/Password** | Used by user signup and astrologer signup. Free. |
| **Google** | Set the provider's **support email**. Add your debug + release **SHA-1/SHA-256** keys under Project settings → Your apps → Android, then re-download `google-services.json` (or re-run `flutterfire configure`). Get the debug SHA-1 with `cd android && ./gradlew signingReport`. |
| **Phone** | Used for OTP login. Requires the **Blaze plan** for real SMS beyond the free daily quota, plus SHA keys + Play Integrity. For testing, add test phone numbers under Phone → "Phone numbers for testing". |

## 3b. App Check (REQUIRED — sign-in fails without it)

If **App Check enforcement** is ON for Authentication or Firestore, a build that
does not send an App Check token is rejected. A brand-new Google account sees:

```
An internal error has occurred.
Firebase App Check token is invalid.
```

The app installs a provider at startup (`lib/core/config/app_check_config.dart`,
called from `main()`), but the provider still has to be registered in the
console:

**Release builds — Play Integrity**

1. Firebase Console → **Build → App Check → Apps → your Android app**.
2. Register the **Play Integrity** provider.
3. Paste the **SHA-256** of the key that signs the build you are testing.
   * Uploading to Play → use the **App signing key** SHA-256 from
     *Play Console → Setup → App integrity* (NOT the upload key).
   * Sideloading a locally-signed release → use the upload key's SHA-256:
     `keytool -list -v -keystore android/upload-keystore.jks -alias <alias>`
4. Link the app in *Play Console → Setup → App integrity* so Play Integrity can
   verify it.

**Debug / `flutter run` builds — debug provider**

1. Run the app once and find this line in logcat:
   `Enter this debug secret into the allow list in the Firebase Console: <uuid>`
2. Firebase Console → **App Check → Apps → your app → ⋮ → Manage debug tokens**
   → add that UUID.
3. The token is per-install: a new device or a fresh install needs a new one.

**Rolling it out safely.** Turn enforcement ON only after the *Requests* tab in
App Check shows verified traffic — enabling it early locks out every existing
installed build.

**Verifying.** `AppCheckConfig.activate()` logs `[AppCheck] activated (...)` on
success and never throws. If sign-in still fails, the app now surfaces the real
reason ("Sign-in was blocked by Firebase App Check…") instead of Firebase's
generic internal error.

## 4. Create Firestore

1. **Build → Firestore Database → Create database** (production mode,
   `asia-south1` is closest for Tamil Nadu users).
2. Deploy the security rules from this repo:

```bash
npm install -g firebase-tools
firebase login
firebase init firestore   # choose existing project, point to firestore.rules
firebase deploy --only firestore:rules
```

Collections are created automatically by the app on first write — no manual
setup needed. The app uses:

| Collection | Purpose |
|---|---|
| `users/{uid}` | Account doc: role (`user`/`astrologer`/`admin`), name, phone, gender, dateOfBirth, location, profileId, membership |
| `profiles/{id}` | Full matrimony profiles (personal, horoscope, family, preferences, contact) |
| `astrologers/{uid}` | Astrologer accounts: experience, specialization, location, services, verification status |
| `astrologer_requests/{id}` | Consultations, inquiries, horoscope-matching requests (`type`, `status`, `amount`) |
| `bookings/{id}` | Appointments between users and astrologers |
| `chats/{threadId}` + `messages` subcollection | 1-to-1 realtime chat |
| `interests/{id}` | Interest (like) requests between profiles |
| `notifications`, `subscriptions`, `reports`, `transactions` | Supporting features |

Composite indexes: Firestore will print a console link the first time a
filtered+ordered query runs (e.g. `astrologer_requests` by `astrologerId` +
`createdAt`); click it to create each index — or add them in
**Firestore → Indexes**.

## 5. Storage (profile photos, horoscope PDFs, ID proof)

> **This step is now optional.** Profile media currently uploads to
> **Cloudinary** instead of Firebase Storage, because Firebase Storage
> requires the project to be on the **Blaze** (pay-as-you-go) plan. See
> [`CLOUDINARY_SETUP.md`](./CLOUDINARY_SETUP.md) for the active
> configuration. The steps below are only needed if you switch
> `storageServiceProvider` back to `FirebaseStorageService` (1-line change in
> `lib/providers/service_providers.dart`) once your project is on Blaze.

**Build → Storage → Get started.** Used for profile photos
(`profiles/{uid}/photos/`), horoscope PDFs/images
(`profiles/{uid}/horoscope/`), and ID-proof docs (`profiles/{uid}/id_proof/`).

Then deploy the Storage security rules from this repo (`storage.rules`):

```bash
firebase deploy --only storage
```

> If profile submission fails with
> `[firebase_storage/object-not-found] No object exists at the desired
> reference.`, Storage hasn't been enabled for this project yet (the upload
> silently has nowhere to land) — do the "Get started" step above, then
> deploy the rules and retry. `[firebase_storage/unauthorized]` means Storage
> is enabled but `storage.rules` hasn't been deployed yet.

## 6. Switch off demo mode

In `lib/core/config/dev_config.dart`:

```dart
const bool kBypassAuth = false;
```

Then run:

```bash
flutter pub get
flutter run
```

## 7. End-to-end flow (what to expect)

1. **Splash** → **"Who are you creating an account for?"** (User / Astrologer).
2. **User** → login (Phone OTP / Email / Google) or signup
   (name, mobile, gender, DOB, location) → saved to `users/{uid}` → **Home**.
3. **Home** → header (photo, name, notifications), profile-completion card
   (% + missing fields + Complete Profile), realtime profile cards with
   **View / Interest / Chat** actions.
4. **Astrologer** → its own login/signup (name, mobile, experience,
   specialization, location) → saved to `astrologers/{uid}` with
   `role: astrologer` → **Dashboard** (overview stats, consultation /
   inquiry / matching requests with Accept-Decline-Complete, appointments,
   earnings, reviews, profile).
5. Signing in later routes by role automatically (user → Home,
   astrologer → Dashboard, admin → Admin).

## 8. Troubleshooting "Google Sign-In failed"

Run the automated check first — it compares every signing key this project can
produce against the OAuth clients registered in `google-services.json`, and
prints exactly what to paste where:

```bash
dart run tool/check_google_signin_config.dart
```

### ⚠️ Release builds: the upload key's SHA-1 is NOT registered

`google-services.json` currently contains **one** Android OAuth client, for the
debug keystore:

| Key | SHA-1 | Registered? |
|---|---|---|
| `ci/debug.keystore` (debug builds) | `8B:4E:88:65:BD:95:8B:9B:46:60:32:B4:C8:D7:32:4D:87:7B:AD:BE` | ✅ yes |
| `android/upload-keystore.jks` (release / Play builds) | `06:9B:78:84:FF:CE:C2:00:C3:F0:C8:C8:D3:96:3B:71:60:18:A7:62` | ❌ **no** |

Its SHA-256 is
`1F:27:69:28:5F:37:E1:D7:A0:E4:AE:E0:80:11:14:38:6B:B6:6F:3B:81:75:FE:B5:C2:23:30:D0:D2:7D:BB:09`.

Because of that, **any release build signs in fine in debug and fails in
release**: Google returns no ID token for an unregistered signing certificate,
so the Firebase credential exchange never happens. No amount of Dart code can
work around it. Fix it once, in the console:

1. Firebase Console → **Project settings** → *Your apps* → the Android app
   `com.jothida.jothida_matrimony` → **Add fingerprint**.
2. Paste the release SHA-1 above. Repeat for the SHA-256.
3. **If the app ships through Google Play** (Play App Signing), Play re-signs
   the bundle with its own key. Copy the SHA-1 **and** SHA-256 from Play
   Console → *Release* → *Setup* → **App signing** → "App signing key
   certificate" and add those too — that is the certificate on the device that
   users actually install.
4. Re-download `google-services.json` into `android/app/`, then rebuild.
5. Re-run `dart run tool/check_google_signin_config.dart` — it should print
   *All checks passed*.

### Other causes

If the fingerprints are all registered and you still see a sign-in error, the
cause is almost always elsewhere in the **Google Cloud / Firebase console**,
not the code:

| Error code | Meaning | Fix |
|---|---|---|
| `ApiException: 10` (DEVELOPER_ERROR) | SHA-1/SHA-256 fingerprint or package name not registered for the OAuth client. | In Firebase Console → Project settings → Your apps → Android, add the **debug** SHA-1 above (and your **release** SHA-1 once you have one), then re-download `google-services.json`. |
| `ApiException: 12500` (SIGN_IN_FAILED) | The OAuth consent screen isn't fully configured, or the signing-in account isn't permitted yet. | In Google Cloud Console → APIs & Services → OAuth consent screen: set a **support email**, add the app, and either **publish** the app or add the test Google account under **Test users**. Also make sure Google Play Services is up to date on the device/emulator and that the device has at least one Google account signed in. |
| `ApiException: 7` | No network. | Check device connectivity. |
| `account-exists-with-different-credential` | The email is already registered via Email/Password or Phone. | Sign in with the original method, or enable account linking. |

The app decodes the underlying `ApiException` code and shows one of the messages
above instead of a generic "Google Sign-In failed. Please try again.", so check
the SnackBar text for the specific code.

### Reading the log

Every phase of the flow is logged with its elapsed time, so a failure is visible
in `flutter logs` / `adb logcat` without a debugger. A healthy sign-in looks
like this:

```
[GoogleSignIn +2ms]     opening the Google account picker...
[GoogleSignIn +4210ms]  account selected: someone@gmail.com
[GoogleSignIn +4890ms]  tokens received (idToken=true, accessToken=true)
[GoogleSignIn +4891ms]  exchanging the Google credential with Firebase...
[GoogleSignIn +5620ms]  Firebase sign-in succeeded. uid=abc123, isNewUser=false
[AuthRepository] _onAuthenticated: createOrUpdateUserOnLogin(abc123, ...)
[Firestore] abc123: existing doc found → refreshing lastLoginAt/loginProvider
[AuthRepository] _onAuthenticated: Firestore doc ready.
[LoginScreen] Sign-in successful (uid=abc123). Routing...
[LoginScreen] routeAuthenticatedUser: profile complete → /home
```

Whatever line it stops after tells you which step failed:

| Last line | Failing step |
|---|---|
| `opening the Google account picker...` | Play Services / the picker — see `watchdog:` lines below it. |
| `account selected: ...` then `idToken=false` | The signing certificate is not registered (the table above). |
| `exchanging the Google credential...` | Firebase Auth — provider disabled, or no network. |
| `createOrUpdateUserOnLogin` with no `doc ready` | Firestore — rules not deployed (`permission-denied`) or offline. |

## 9. Optional

- **FCM push notifications**: already initialised in `main.dart`; upload your
  APNs key for iOS.
- **Admin account**: set `role: "admin"` manually on a user document in the
  Firestore console to unlock the admin panel.
- **Razorpay**: put your key in `.env` (`RAZORPAY_KEY_ID=...`) for
  subscription payments.
