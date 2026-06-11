# Jothida Matrimony — Firebase Production Migration Plan

_Generated: 2026-06-11_

## 1. Current State Assessment

### Good news: the Firebase architecture already exists

The codebase is **not** a from-scratch demo — it already has a real service/repository layer wired for Firebase:

- `lib/services/firebase/auth_service.dart` — phone OTP, email/password, Google sign-in
- `lib/services/firebase/firestore_service.dart` (349 lines) — users, profiles, interests, subscriptions, admin, notifications
- `lib/services/firebase/storage_service.dart` — photo & horoscope PDF uploads
- `lib/services/firebase/fcm_service.dart` — token management, background handler stub
- `lib/services/firebase/chat_service.dart` — Firestore chat threads/messages
- `lib/services/firebase/astrologer_service.dart` — astrologer accounts/requests
- `lib/repositories/*` — clean repository layer the UI calls (never touches Firebase directly)
- `firestore.rules` — a fairly complete security rules draft already written
- `pubspec.yaml` already includes `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`, `google_sign_in`

This significantly reduces the work — the migration is mostly **wiring real config + removing the demo bypass layer**, not building Firebase integration from zero.

### What is mock / demo / placeholder right now

| Area | File(s) | Issue |
|---|---|---|
| **Firebase project config** | `lib/firebase_options.dart`, `android/app/google-services.json`, `.env` | All structurally-valid but **fake** placeholder values (`jothida-matrimony-placeholder`, `REPLACE_WITH_YOUR_PROJECT_ID`, `YOUR_API_KEY_HERE`) |
| **Global auth bypass** | `lib/core/config/dev_config.dart` (`kBypassAuth = true`) | Disables the router's auth guard; "Continue with Google" skips real sign-in |
| **Demo profile store** | `lib/providers/demo_data_provider.dart`, `lib/core/data/sample_profiles.dart` | In-memory list of fake profiles used for Discover / My Profile / Match details when `kBypassAuth` is true |
| **Profile creation (demo path)** | `lib/providers/profile_provider.dart` (`submitProfile`, `myProfileProvider`, `profileByIdProvider`, `DiscoverNotifier.load`) | When `kBypassAuth`, writes to in-memory store instead of Firestore, uses placeholder photo URLs (`randomuser.me`) |
| **Astrologer directory** | `lib/providers/astrologer_provider.dart`, `lib/core/data/sample_astrologers.dart` | **Always** hardcoded — not even gated by `kBypassAuth`. Has a `// TODO(backend)` comment |
| **Astrologer dashboard** | `lib/providers/astrologer_session_provider.dart`, `lib/core/data/sample_astrologer_dashboard.dart` | Bookings, reviews, availability, and (in demo mode) consultation requests are **always** sample/in-memory data |
| **Chat** | `lib/providers/chat_provider.dart` (`DemoChatNotifier`, `demoChatProvider`) | Full in-memory chat implementation used when `kBypassAuth` |
| **Auth-bypass branches in screens** | `login_screen.dart`, `register_screen.dart`, `astrologer_login_screen.dart`, `astrologer_register_screen.dart`, `astrologer_dashboard_screen.dart`, `profile_creation_screen.dart` | Each has `if (kBypassAuth) { ... }` shortcuts that skip Firebase calls |
| **Router auth guard** | `lib/router/app_router.dart` | `if (kBypassAuth) return null;` — disables redirect logic entirely |
| **Razorpay** | `lib/core/constants/razorpay_constants.dart`, `.env` | Test key placeholders (`rzp_test_XXXX...`) |
| **iOS platform** | — | No `ios/` directory exists — Android-only project currently |

### What is missing entirely (not started)

- **Firebase Analytics** — `firebase_analytics` not in `pubspec.yaml`, no usage anywhere
- **Firebase Crashlytics** — `firebase_crashlytics` not in `pubspec.yaml`, no global error handler wired to it
- **Storage security rules** — no `storage.rules` file
- **Firebase CLI project files** — no `firebase.json` / `.firebaserc` (needed to deploy Firestore/Storage rules and indexes)
- **Firestore composite indexes** — `firestore.indexes.json` not present (Discover/search filters will need them)
- **FCM notification channel (Android 8+)** — `AndroidManifest.xml` has the `POST_NOTIFICATIONS` permission but no default notification channel/icon configured
- **iOS push (APNs)** — no iOS project, so no APNs key/certificate setup yet

### What's already solid (verified)

- `firestore.rules` covers users, profiles, interests, subscriptions, poruthams, reports, notifications, transactions, astrologers, astrologer_requests, bookings, chats/messages — good foundation, will need a final review pass
- `AuthException` (`lib/core/errors/auth_exception.dart`) already normalizes Firebase/Google/Platform exceptions into user-friendly messages
- `android/app/build.gradle` already has `minSdk = 23` (required by `firebase_auth`) and the `google-services` Gradle plugin applied, plus a pinned debug keystore for consistent SHA-1
- `main.dart` already calls `Firebase.initializeApp()` and `FcmService().initialize()` (wrapped in try/catch so it doesn't block the demo UI)

---

## 2. Migration Plan (step-by-step)

We will go through these **one at a time**, waiting for your confirmation after each:

1. **Firebase project setup & FlutterFire configuration** — create/connect the real Firebase project, run `flutterfire configure`, replace all placeholder config files (`firebase_options.dart`, `google-services.json`, `.env`), add iOS/Web if needed.
2. **Remove `kBypassAuth` & wire real Authentication** — delete the dev bypass flag, restore the router auth guard, fix every `if (kBypassAuth)` branch in auth screens to use real Firebase Auth (phone OTP / email / Google).
3. **Profiles & Discover → Firestore** — remove `demo_data_provider.dart` / `sample_profiles.dart`, route `myProfileProvider`, `profileByIdProvider`, `DiscoverNotifier`, and `ProfileCreationNotifier` fully through `ProfileRepository`/Firestore + Storage.
4. **Astrologer module → Firestore-backed** — replace `sample_astrologers.dart` and `sample_astrologer_dashboard.dart` with real Firestore queries (directory listing, dashboard stats, bookings, reviews, availability, requests).
5. **Chat → Firestore-backed** — remove the in-memory `DemoChatNotifier`, route everything through `ChatService`.
6. **Storage hardening** — verify photo/PDF upload paths, write `storage.rules`, test end-to-end uploads.
7. **Production push notifications (FCM)** — background handler, Android notification channel, iOS APNs, token lifecycle, tap-to-navigate.
8. **Analytics & Crashlytics** — add packages, initialize, global error capture, key event logging.
9. **Security rules finalize & deploy** — review `firestore.rules`, write `storage.rules`, add `firebase.json`/`.firebaserc`/indexes, deploy via Firebase CLI.
10. **Session persistence & error handling/logging audit** — confirm auth persistence across restarts, centralized logging, no-data-loss checks (esp. profile creation/photo upload failure paths).
11. **Razorpay production config** — move keys to `.env`, switch test→live key path, verify subscription writes to Firestore.
12. **Final QA** — `flutter analyze`, builds for each target platform, full smoke test of signup → profile → discover → interest → chat → notification → subscription.

---

## 3. Open questions before Step 1

- Do you already have a **Firebase project** created (Console), or should we create one from scratch?
- **Target platforms**: Android only, or also iOS and/or Web? (No `ios/` folder currently exists — adding iOS is extra setup.)
- Do you have the **Firebase CLI** and **FlutterFire CLI** installed locally, or do we need to set those up first?
