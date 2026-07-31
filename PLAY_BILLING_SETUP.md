# Google Play Billing setup — `horoscope_report`

The app was migrated from Razorpay to the official Google Play Billing plugin
(`in_app_purchase`). The paid **Horoscope Analysis report** is a one-time
(consumable) product. This doc is the Play Console checklist to make the
purchase work in production.

## What's already in the code

- Dependency: `in_app_purchase` (see `pubspec.yaml`) — Razorpay removed.
- Service: `lib/services/billing/play_billing_service.dart` — init, product
  loading, purchase, lifecycle (purchased / pending / canceled / error /
  restored), client-side verification + `completePurchase`.
- Product id constant: `BillingProducts.horoscopeReport = 'horoscope_report'`.
- Purchase entry point: **Horoscope Analysis** screen
  (`lib/screens/astrology/horoscope_report_service_screen.dart`) → buy →
  verify → save to Firestore → unlock on the Reports tab.
- Android permission: `com.android.vending.BILLING` in
  `android/app/src/main/AndroidManifest.xml`.

## Play Console steps (do these after uploading the new AAB)

1. **Build & upload an AAB** that contains this billing code to an internal
   testing (or higher) track — a product can only be tested once a build that
   references it has been uploaded at least once.
2. Play Console → your app → **Monetize with Play → Products → One-time
   products** (a.k.a. "In-app products").
3. **Create product**:
   - **Product ID:** `horoscope_report`  ← must match exactly (case-sensitive).
   - Name / description: e.g. "Horoscope Analysis Report".
   - **Price:** set your price (e.g. ₹199).
4. **Save**, then **Activate** the product (status must be **Active** — an
   inactive product returns "not found" and the purchase can't start).
5. **License testers:** Play Console → Setup → **License testing** → add the
   Google accounts that will test, so purchases are free/sandbox for them.
6. Install the app from the **same track** (internal testing link) on a device
   signed in with a license-tester account, and buy the report.

## Notes / follow-ups

- **Consumable:** the product is consumed on delivery (`autoConsume: true`), so a
  member can buy another report for a different match.
- **Server-side verification (recommended for production):** verification is
  currently **client-side** (see the `TODO(server)` in `_verifyPurchase`). For
  tamper-proof entitlement, verify the purchase token against the Google Play
  Developer API from a trusted backend (a Cloud Function) before granting the
  report. The purchase token is already saved with the request so a backend can
  reconcile it.
- **Other flows:** the in-person astrology **appointment** and the **external
  report** request no longer charge in-app (Razorpay removed; Play Billing can't
  be used for a real-world/in-person service). They now proceed for free and are
  auto-assigned for verification. If you later want to charge for the external
  (digital) report, add a second one-time product id and route it through
  `PlayBillingService.buyConsumable` the same way.
