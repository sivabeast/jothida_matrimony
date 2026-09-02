# Horoscope ₹199 · Matches · App Version — release notes (v1.15.0+21)

What changed, and what has to be done outside the codebase for it to work.

---

## ⚠️ Required after merging

### 1. Deploy the security rules — **mandatory**

```bash
firebase deploy --only firestore:rules
```

Two things depend on it:

- **The ₹199 is now enforced server-side.** A `matching` request is refused
  unless it carries `paid: true`, `amount >= 199` and a real Play purchase
  token. Until the rules are deployed the old ones still allow a guest request
  only when `amount == 0`, so **every paid horoscope request will be rejected**.
- **`profile_browsing/{uid}`** — the new per-member document behind the daily
  5-new-profile limit. Without the rule, reads and writes are denied and the
  limit falls back to the on-device copy only.

### 2. Set the Play Console price to ₹199

Play Console → Monetize → Products → One-time products → `horoscope_report` →
price **₹199**. Play Console is the source of truth: the app shows Play's own
price and records what Play actually charged. The `199` in the code is the
fallback label and the floor the rules insist on, so a Play price *below* ₹199
would start failing the rules.

### 3. (Optional, needs Blaze) Server-side purchase verification

`functions/index.js` now has **`verifyPlayPurchase`**, which checks a purchase
token against the Google Play Developer API from a trusted backend. It is not
deployed yet — the project is on the Spark plan and Cloud Functions need Blaze.

Until it is deployed the app verifies purchases locally, stamps the request
`payment.verifiedBy: 'client'`, and keeps working. Nothing breaks; those
requests simply have not been confirmed with Play.

To turn it on:

1. Google Play Console → Users and permissions → invite
   `<projectId>@appspot.gserviceaccount.com` and grant **View financial data**.
2. Google Cloud Console → enable **Google Play Android Developer API**.
3. `firebase deploy --only functions:verifyPlayPurchase`

From then on requests are stamped `verifiedBy: 'server'` and a token Play
rejects fails the purchase outright.

---

## Two places where the request was written against a different stack

**Razorpay.** The spec asked for Razorpay. Razorpay was removed from this app in
an earlier release and replaced with Google Play Billing, because Google Play's
Payments policy requires Play Billing for digital goods sold in an Android app —
a ₹199 horoscope report is digital goods, and shipping Razorpay for it risks the
listing being rejected or removed. The ₹199 gate is therefore built on the
existing Play Billing integration, which gives the same guarantees the spec
asked for: an order created by the store, a purchase token, server-side
verification, and no request written before a verified purchase.

**PHP.** There is no PHP anywhere in this project. The backend is Firebase —
Firestore security rules plus Cloud Functions in JavaScript. Adding PHP would
have meant introducing a new language *and* a new server, and it could not
enforce Firestore rules in any case. The server-side work is in
`firestore.rules` and `functions/index.js`.

---

## What shipped

### Horoscope request (§1–§3, §12)

- Four steps: **Person 1 → Person 2 → Contact → Review & Pay**.
- Person 1 loads from the profile automatically. No "Use my profile details"
  button; a single **Clear** empties the card for somebody else.
- Gender is stated, not asked: Person 1's comes from the profile, Person 2's is
  its opposite. Only a cleared Person 1 is ever asked, once.
- **Female → Bride, Male → Groom**, resolved once at submission and stored on
  the request (`lib/core/utils/horoscope_roles.dart`).
- **₹199 once per complete request** — both charts, one charge. The request
  document is written only after a verified purchase; a cancelled, failed or
  abandoned payment leaves nothing behind and can be retried. A payment that
  succeeded but whose write failed re-uses the token instead of charging twice.
- **Free sample report** (`SampleCompatibilityReportScreen`), reachable from the
  first screen of both paid entry points, viewable and downloadable as the same
  A4 PDF a real report produces, labelled SAMPLE in four places.

### Employee / admin (§4)

- No "Other Party (not a member)" section anywhere. Every request — manual or
  member-to-member — shows the same **மணமகன் (Groom)** and **மணமகள் (Bride)**
  cards, filled from the request.
- Name, DOB, birth time, birth place, star and rasi are never re-keyed; the
  employee fills only the analysis.

### Matches (§6–§9)

- Caste + age remain the primary hard filters; other set preferences still
  filter, and rank.
- **Nakshatra is no longer a filter anywhere** — the Partner Preferences option
  is gone, `MatchFilters` has no nakshatra field, and it no longer counts in the
  preference score. Star compatibility still drives the ⭐ badge and is the first
  sort key.
- **5 new profiles a day.** Already-seen profiles are free and unlimited for
  ever; the pager ends on a live countdown to the next reset instead of a blank
  "no more profiles"; tomorrow continues at the sixth. State lives in
  `profile_browsing/{uid}` so clearing app data does not reset it.

### App version (§10)

- Admin can no longer type or increase a version number. The screen is read-only
  version information plus **one** switch: Force Update on/off.
- Current version comes from `PackageInfo`; the latest published version from
  Google Play's In-App Update API and from the newest build publishing its own
  metadata; the minimum supported version from
  `kMinimumSupportedVersionCode` in `lib/core/config/release_config.dart`,
  which travels with the release.
- Raise that constant **only** when an old build genuinely must stop working —
  it locks those members out.

### Localization (§5)

- The astrology page's admin-managed content (services, experience,
  specialization, intro) now renders in Tamil for the strings the app ships;
  admin-rewritten text is shown as typed.
- The compatibility report screen is localized.
- Every new card uses intrinsic heights, `Wrap` instead of `Row` where Tamil
  runs wide, and multi-line labels — covered by widget tests at 360 px in Tamil.
