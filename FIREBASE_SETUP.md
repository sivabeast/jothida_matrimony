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

## 8. Optional

- **FCM push notifications**: already initialised in `main.dart`; upload your
  APNs key for iOS.
- **Admin account**: set `role: "admin"` manually on a user document in the
  Firestore console to unlock the admin panel.
- **Razorpay**: put your key in `.env` (`RAZORPAY_KEY_ID=...`) for
  subscription payments.
