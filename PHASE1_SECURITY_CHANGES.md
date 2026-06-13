# Phase 1 — Security & Privacy Conformance

Brings the app in line with the *Matrimony + Astrologer Marketplace* source-of-truth
on the **security-critical** rules: user privacy, astrologer-no-browse, verified-only
visibility, and contact-on-acceptance. (Astrologer subscriptions = Phase 2.)

## What changed

**Firestore rules (`firestore.rules`) — must redeploy**
- Astrologers can no longer read `users` or `profiles` (removed the blanket
  `isAdminOrAstrologer` read). Enforces "astrologers never browse user data / get
  phone numbers." Same removal applied to `poruthams`.
- `notifications` create restricted to admins only (was admin **or astrologer**),
  and astrologers can no longer create `chats` threads — closes the two
  astrologer→user contact channels.
- `astrologers` read restricted to `status == 'approved'` (plus owner/admin), so
  unverified astrologers are invisible to users at the data layer.
- New `contacts/{userId}` and `connections/{pair}` collections: contact details are
  readable only by the owner, an admin, or a user with an **accepted** connection.
  A connection can only be created when a *real* accepted interest references both
  parties — blocking self-granted unlocks.

**Storage rules (`storage.rules`) — must redeploy**
- ID-proof documents (`profiles/{uid}/id_proof/**`) are now readable only by the
  owner and admins (were readable by every signed-in user). Photos and horoscope
  files remain visible to signed-in users.

**App code**
- `astrologer_provider.dart`: user-facing directory now uses
  `watchApprovedAstrologers()` (verified-only) instead of "all except rejected".
- Contact moved out of the public profile:
  - `ProfileModel.toFirestore()` no longer writes `contact`.
  - `FirestoreService.createProfile()` writes contact to `contacts/{userId}`.
  - New `getContact` / `saveContact`, `getInterestById`, and
    `acceptInterestAndConnect` (accept → write `connections/{pair}`).
  - `interest_repository.acceptInterest()` now records the connection on accept.
  - New `contactByUserIdProvider` + `ContactRevealCard` widget; shown on the match
    screen, it reveals contact when unlocked and a "locked" state otherwise.

## Deploy steps (in order)
1. Review the diff.
2. `firebase deploy --only firestore:rules,storage` (deploy the new rules **first**).
3. Run the one-time migration: `scripts/migrate_contacts.js` (moves existing
   `profiles.contact` → `contacts/{userId}` and strips the field).
4. Ship the updated app build.

## Verification status
- Static cross-checks done: new symbols/imports resolve, rule string literals match
  (`interestAccepted == 'accepted'`), admin queries still valid under the tightened
  astrologer rule, no dangling helper references.
- **Not run here:** no Flutter SDK in this environment. Please run `flutter analyze`
  and `flutter test` before shipping.

## Known follow-ups (not in Phase 1)
- The **interests tab UI** still uses the in-memory demo store (`requests_provider`);
  the real contact-unlock fires on the Firestore path (`interest_provider`). Migrate
  the tab to the Firestore-backed providers so accept→unlock works end-to-end in prod.
- **Phase 2:** astrologer subscription model (Monthly/Yearly) + hide on expiry, and
  server-side Razorpay verification before granting premium/active status.
