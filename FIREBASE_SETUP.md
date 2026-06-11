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

## 5. Enable Storage

**Build → Storage → Get started.** Used for profile photos
(`profile_photos/`) and horoscope documents (`horoscope_docs/`).

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

This project's Android config (`android/app/google-services.json`,
`android/app/build.gradle`, `ci/debug.keystore`) is already set up consistently:
package `com.jothida.jothida_matrimony`, project `matrimony-app-bd0d5`, and the
debug keystore's SHA-1 (`8B:4E:88:65:BD:95:8B:9B:46:60:32:B4:C8:D7:32:4D:87:7B:AD:BE`)
matches the OAuth Android client in `google-services.json`. If you still see a
sign-in error, the cause is almost always in the **Google Cloud / Firebase
console**, not the code:

| Error code | Meaning | Fix |
|---|---|---|
| `ApiException: 10` (DEVELOPER_ERROR) | SHA-1/SHA-256 fingerprint or package name not registered for the OAuth client. | In Firebase Console → Project settings → Your apps → Android, add the **debug** SHA-1 above (and your **release** SHA-1 once you have one), then re-download `google-services.json`. |
| `ApiException: 12500` (SIGN_IN_FAILED) | The OAuth consent screen isn't fully configured, or the signing-in account isn't permitted yet. | In Google Cloud Console → APIs & Services → OAuth consent screen: set a **support email**, add the app, and either **publish** the app or add the test Google account under **Test users**. Also make sure Google Play Services is up to date on the device/emulator and that the device has at least one Google account signed in. |
| `ApiException: 7` | No network. | Check device connectivity. |
| `account-exists-with-different-credential` | The email is already registered via Email/Password or Phone. | Sign in with the original method, or enable account linking. |

The app now decodes the underlying `ApiException` code and shows one of the
messages above instead of a generic "Google Sign-In failed. Please try again.",
so check the SnackBar text (or `[AuthService] signInWithGoogle failed: ...` in
logcat) for the specific code.

## 9. Optional

- **FCM push notifications**: already initialised in `main.dart`; upload your
  APNs key for iOS.
- **Admin account**: set `role: "admin"` manually on a user document in the
  Firestore console to unlock the admin panel.
- **Razorpay**: put your key in `.env` (`RAZORPAY_KEY_ID=...`) for
  subscription payments.
