# Push Notifications & Reminders — Setup / Deploy

This covers the Firebase Cloud Messaging (FCM) push system added for the
astrologer module (spec §8/§9/§12): real device push for new bookings, the
6h / 3h / 1h acceptance reminders, and auto-expiry.

Everything in the **app** is already wired (token registration on login,
foreground banner, tap-to-open booking, in-app notification history). The only
thing that requires you to act is deploying the Cloud Functions, because real
device push cannot be sent from the client alone.

## What is automatic (already in code)

- `lib/services/firebase/fcm_service.dart` — permission, token, foreground
  banner, tap → deep-link to the booking.
- Token saved to `users/{uid}.fcmToken` on every login
  (`AuthRepository._registerFcmToken`).
- Every event writes a `notifications/{id}` doc with a `data.route` deep link.
- `functions/index.js` — turns each notification doc into a push, and runs the
  scheduled reminder + expiry sweep.

## Manual steps (do these once)

1. **Upgrade the Firebase project to the Blaze (pay-as-you-go) plan.**
   Cloud Functions and Cloud Scheduler require Blaze. (Free tier quotas are
   generous; this project's usage is tiny.)
   Firebase Console → ⚙️ → Usage and billing → Modify plan → Blaze.

2. **Enable the required APIs** (Blaze usually enables them automatically; if a
   deploy complains, enable manually in Google Cloud Console):
   - Cloud Functions API
   - Cloud Build API
   - Cloud Scheduler API (for the `every 30 minutes` job)
   - Eventarc API + Artifact Registry API (for v2 Firestore triggers)

3. **Confirm Cloud Messaging is enabled.**
   Firebase Console → Project settings → Cloud Messaging. The Android app
   (`google-services.json`) and, if you ship iOS, an **APNs key** must be
   configured under Cloud Messaging for iOS pushes.

4. **Install the Firebase CLI** (if you don't have it) and log in:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```

5. **Install function deps and deploy:**
   ```bash
   cd functions
   npm install
   cd ..
   firebase deploy --only functions
   ```
   This deploys two functions:
   - `onNotificationCreated` (Firestore `notifications/{id}` onCreate → push)
   - `matchAnalysisSweep` (Cloud Scheduler, every 30 min, Asia/Kolkata)

6. **(Android, optional but recommended) default notification channel.**
   Pushes use channel id `high_importance_channel`. Android auto-creates a
   fallback channel, so notifications still appear without extra work. If you
   want a branded channel, add `flutter_local_notifications` and create it on
   app start — not required for delivery.

7. **(iOS only)** Upload the APNs Authentication Key (.p8) in
   Project settings → Cloud Messaging, and enable Push Notifications +
   Background Modes (Remote notifications) capabilities in Xcode.

## How the timing works

- A match-analysis booking is created with `expiresAt` = **12 working hours**
  after creation, where working hours exclude **00:00–07:00 IST**
  (`lib/core/utils/working_hours.dart`).
- The on-device countdown (`BookingCountdown`) shows the remaining working time
  and recolours green → orange → red, then "Acceptance Expired".
- `matchAnalysisSweep` recomputes the same working-time server-side to fire the
  6h / 3h / 1h reminders (skipped during 00:00–07:00 IST) and to set
  `expired: true` once the deadline passes.

## Quick test

1. Sign in on a real device (token registers).
2. As a user, book & pay for a match analysis.
3. The astrologer device should receive **"New Match Analysis Request"** and the
   dashboard banner + Requests badge should appear.
4. Tap the push → it opens the booking workspace.
5. Inspect logs: `firebase functions:log`.
