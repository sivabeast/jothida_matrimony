import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/app_constants.dart';
import '../firebase/callable_functions_client.dart';
import '../firebase/firestore_service.dart';

/// The Play Console product IDs. Create + ACTIVATE these under
/// Play Console → Monetize with Play → Products → One-time products.
class BillingProducts {
  BillingProducts._();

  /// One-time (consumable) product that unlocks a single Horoscope Analysis
  /// report. Consumable so a member can buy another report for a different
  /// match. MUST match the Product ID created in Play Console exactly.
  static const String horoscopeReport = 'horoscope_report';

  static const Set<String> all = {horoscopeReport};
}

/// What a purchase attempt resolved to, surfaced to the UI so it can react
/// (unlock / show a message / reset its button).
enum BillingOutcome { purchased, pending, canceled, error, unavailable }

/// How a purchase was checked before it was accepted (spec §2C).
enum BillingVerification {
  /// Google Play itself confirmed the token, via the `verifyPlayPurchase`
  /// Cloud Function. The only verdict that cannot be forged by a tampered app.
  server,

  /// The backend verifier is not deployed / not yet authorised in Play Console,
  /// so only the local check ran. Recorded on the request so these can be
  /// reconciled against Play later.
  client,
}

class BillingResult {
  final BillingOutcome outcome;
  final String productId;

  /// The Play purchase token (`serverVerificationData`) — persisted with the
  /// unlocked entitlement and what the server-side verifier checks.
  final String purchaseToken;

  /// Which check actually passed. Callers store this alongside the token.
  final BillingVerification verification;

  /// Play's own order id when the server verifier returned one — the reference
  /// an admin reconciles against Play's records.
  final String orderId;

  final String? message;

  const BillingResult(
    this.outcome, {
    this.productId = '',
    this.purchaseToken = '',
    this.verification = BillingVerification.client,
    this.orderId = '',
    this.message,
  });

  bool get isPurchased => outcome == BillingOutcome.purchased;
}

/// Google Play Billing wrapper built on the official `in_app_purchase` plugin —
/// the single replacement for the removed Razorpay integration.
///
/// Responsibilities (spec Task 1): billing initialization, product loading, a
/// one-time (consumable) purchase, and the full purchase lifecycle — success,
/// pending, cancellation, failure and restoration — with client-side
/// verification and correct purchase completion (acknowledge/consume).
///
/// Lifecycle: create ONE instance for the app (see `playBillingServiceProvider`)
/// so a single `purchaseStream` listener owns every update. `buyConsumable`
/// launches the Play sheet and completes when the stream reports a terminal
/// state for that product.
/// What [PlayBillingService._verifyPurchase] concluded, and on whose authority.
class _VerificationOutcome {
  final bool ok;
  final BillingVerification by;
  final String orderId;
  const _VerificationOutcome(this.ok, this.by, {this.orderId = ''});
}

class PlayBillingService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final CallableFunctionsClient _functions = CallableFunctionsClient();

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<String, ProductDetails> _products = {};
  bool _available = false;

  /// One in-flight buy() per product id — the purchase-stream handler resolves
  /// it when Play reports the outcome.
  final Map<String, Completer<BillingResult>> _pending = {};

  bool get isAvailable => _available;
  ProductDetails? product(String id) => _products[id];

  /// Connects to the store and starts listening to the purchase stream. Safe to
  /// call repeatedly; the stream listener is attached once.
  Future<void> init() async {
    _available = await _iap.isAvailable();
    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) => debugPrint('[Billing] purchaseStream error: $e'),
    );
    if (_available) {
      await loadProducts();
    } else {
      debugPrint('[Billing] store unavailable (emulator without Play, or not '
          'signed in to Google Play).');
    }
  }

  /// Loads product details for every id in [BillingProducts.all]. Ids missing
  /// here are usually not-yet-created / inactive in Play Console.
  Future<void> loadProducts() async {
    try {
      final resp = await _iap.queryProductDetails(BillingProducts.all);
      for (final p in resp.productDetails) {
        _products[p.id] = p;
      }
      if (resp.notFoundIDs.isNotEmpty) {
        debugPrint('[Billing] products NOT found: ${resp.notFoundIDs} — create '
            'and ACTIVATE them in Play Console → One-time products.');
      }
    } catch (e) {
      debugPrint('[Billing] loadProducts failed: $e');
    }
  }

  /// The localized store price for [productId] (e.g. "₹199"), or null until the
  /// product is loaded. Lets the UI show Play's real price instead of a
  /// hardcoded amount.
  String? priceLabel(String productId) => _products[productId]?.price;

  /// The numeric store price for [productId] (e.g. `199.0`), or null until the
  /// product is loaded. Used to record what Play ACTUALLY charged, so the
  /// revenue figures stay correct when the Console price is changed without an
  /// app update.
  double? rawPrice(String productId) => _products[productId]?.rawPrice;

  /// Launches the Play purchase sheet for [productId] (a one-time CONSUMABLE
  /// product). Returns once Play reports a terminal outcome for it.
  Future<BillingResult> buyConsumable(String productId) async {
    if (!_available) {
      await init();
    }
    if (!_available) {
      return const BillingResult(BillingOutcome.unavailable,
          message: 'Google Play Billing is unavailable on this device.');
    }
    if (_products[productId] == null) {
      await loadProducts();
    }
    final details = _products[productId];
    if (details == null) {
      return BillingResult(BillingOutcome.error,
          productId: productId,
          message: 'Product "$productId" is unavailable. Ensure it is created '
              'and ACTIVE in Play Console.');
    }

    // Supersede any stale completer for this product so we never leak one.
    _pending.remove(productId)?.complete(
        const BillingResult(BillingOutcome.canceled, message: 'superseded'));
    final completer = Completer<BillingResult>();
    _pending[productId] = completer;

    try {
      // autoConsume so the consumable can be purchased again for another match.
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
        autoConsume: true,
      );
    } catch (e) {
      _pending.remove(productId);
      return BillingResult(BillingOutcome.error,
          productId: productId, message: 'Could not start the purchase: $e');
    }
    return completer.future;
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // Intermediate — leave the awaiting buy() future unresolved.
          break;
        case PurchaseStatus.canceled:
          await _finish(p);
          _resolve(p, BillingOutcome.canceled);
          break;
        case PurchaseStatus.error:
          await _finish(p);
          _resolve(p, BillingOutcome.error, message: p.error?.message);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final v = await _verifyPurchase(p);
          await _finish(p);
          // NEW payments only (not restores) get the "Payment Successful"
          // notification + push. Detached: a notification hiccup must never
          // affect the purchase result.
          if (v.ok && p.status == PurchaseStatus.purchased) {
            unawaited(_notifyPaymentSuccess(p));
          }
          _resolve(p, v.ok ? BillingOutcome.purchased : BillingOutcome.error,
              verification: v.by,
              orderId: v.orderId,
              message: v.ok ? null : 'Purchase verification failed.');
          break;
      }
    }
  }

  /// Verifies a purchase before it is allowed to unlock anything (spec §2C).
  ///
  /// Two layers, in order:
  ///
  ///  1. **Local sanity** — a non-empty token for a product we actually sell.
  ///     Cheap, and it rejects obvious nonsense without a round trip.
  ///  2. **Google Play, via the `verifyPlayPurchase` Cloud Function** — the
  ///     token is checked against the Play Developer API from a trusted
  ///     backend. This is the layer a tampered client cannot fake.
  ///
  /// Fail-closed vs fail-open is decided by WHO said no. A verdict from the
  /// function (`verified: false`, an unknown token, a cancelled purchase) is
  /// final and the purchase is refused. The function being **unreachable** — it
  /// is not deployed yet, the Play service account has not been authorised, or
  /// the device is offline — is not a verdict, and refusing every purchase over
  /// our own missing configuration would be worse than the risk. In that case
  /// the local check stands and the result is stamped
  /// [BillingVerification.client] so the request records how it was accepted.
  Future<_VerificationOutcome> _verifyPurchase(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    if (token.isEmpty || !BillingProducts.all.contains(p.productID)) {
      return const _VerificationOutcome(false, BillingVerification.client);
    }

    try {
      final res = await _functions.call(
        'verifyPlayPurchase',
        data: {'productId': p.productID, 'purchaseToken': token},
        timeout: const Duration(seconds: 20),
      );
      final verified = res['verified'] == true;
      if (!verified) {
        debugPrint('[Billing] Play REJECTED the purchase: ${res['reason']}');
      }
      return _VerificationOutcome(
        verified,
        BillingVerification.server,
        orderId: '${res['orderId'] ?? ''}',
      );
    } on CallableFunctionException catch (e) {
      if (e.isUnavailable || e.code == 'unavailable') {
        debugPrint('[Billing] server verification unavailable ($e) — '
            'accepting on the local check and recording it as unverified.');
        return const _VerificationOutcome(true, BillingVerification.client);
      }
      // A real refusal from the backend (invalid-argument, permission-denied…).
      debugPrint('[Billing] server verification refused the purchase: $e');
      return const _VerificationOutcome(false, BillingVerification.server);
    } catch (e) {
      debugPrint('[Billing] server verification errored ($e) — '
          'falling back to the local check.');
      return const _VerificationOutcome(true, BillingVerification.client);
    }
  }

  /// Writes the in-app "Payment Successful" notification for the signed-in
  /// buyer; the `notifications`-onCreate Cloud Function turns it into the
  /// device push (spec §7 — payment success event).
  ///
  /// DETERMINISTIC doc id — `payment_` + the Play order id (falling back to
  /// the purchase token) — so a redelivered purchase update (stream replay,
  /// app restart before completePurchase) rewrites the SAME document instead
  /// of creating a duplicate, and the onCreate push gate fires at most once.
  ///
  /// Bilingual copy in the RECEIVER's `preferred_language`, mirroring
  /// NotificationNotifier's template pattern. Best-effort: never throws.
  Future<void> _notifyPaymentSuccess(PurchaseDetails p) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Firestore doc ids must not contain '/'; order ids / purchase tokens
      // are URL-safe but sanitize defensively and bound the length.
      String keyOf(String raw) =>
          raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
      var key = keyOf(p.purchaseID ?? '');
      if (key.isEmpty) {
        key = keyOf(p.verificationData.serverVerificationData);
      }
      if (key.length > 120) key = key.substring(key.length - 120);
      if (key.isEmpty) return; // nothing deterministic to key on

      var tamil = false;
      try {
        final snap = await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 8));
        tamil = (snap.data()?['preferred_language'] ?? 'en') == 'ta';
      } catch (_) {/* fall through to English */}

      // Include what Play actually charged when the product is loaded.
      final price = priceLabel(p.productID);
      final amount = (price == null || price.isEmpty) ? '' : ' ($price)';

      final title = tamil ? 'பணம் பெறப்பட்டது ✅' : 'Payment Successful ✅';
      final body = tamil
          ? 'உங்கள் கட்டணம்$amount வெற்றிகரமாக பெறப்பட்டது. உங்கள் ஜாதக '
              'அறிக்கை கோரிக்கை எங்கள் ஜோதிட குழுவிடம் உள்ளது — Reports '
              'பக்கத்தில் பார்க்கவும்.'
          : 'Your payment$amount was received. Your horoscope report request '
              'is with our astrology team — track it in the Reports tab.';

      await FirestoreService().createNotification(
        userId: uid,
        title: title,
        body: body,
        type: 'payment_success',
        data: {'route': '/reports', 'productId': p.productID},
        id: 'payment_$key',
        targetScreen: 'reports',
      );
    } catch (e) {
      debugPrint('[Billing] payment notification failed (non-fatal): $e');
    }
  }

  /// Acknowledges / consumes a purchase so Play stops re-delivering it (and, for
  /// a consumable, so it can be bought again). Must be called for every
  /// non-pending purchase.
  Future<void> _finish(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(p);
      } catch (e) {
        debugPrint('[Billing] completePurchase(${p.productID}) failed: $e');
      }
    }
  }

  void _resolve(
    PurchaseDetails p,
    BillingOutcome outcome, {
    String? message,
    BillingVerification verification = BillingVerification.client,
    String orderId = '',
  }) {
    final c = _pending.remove(p.productID);
    if (c != null && !c.isCompleted) {
      c.complete(BillingResult(
        outcome,
        productId: p.productID,
        purchaseToken: p.verificationData.serverVerificationData,
        verification: verification,
        orderId: orderId,
        message: message,
      ));
    }
  }

  /// Restores previously-owned purchases. A no-op for consumables (the horoscope
  /// report is consumed on delivery), provided for the spec's "Purchase
  /// restoration if applicable" and any future non-consumable products.
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[Billing] restorePurchases failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
