import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/razorpay_constants.dart';

class RazorpayService {
  late Razorpay _razorpay;
  Function(PaymentSuccessResponse)? _onSuccess;
  Function(PaymentFailureResponse)? _onFailure;
  Function(ExternalWalletResponse)? _onExternalWallet;

  void init({
    required Function(PaymentSuccessResponse) onSuccess,
    required Function(PaymentFailureResponse) onFailure,
    Function(ExternalWalletResponse)? onExternalWallet,
  }) {
    _onSuccess = onSuccess;
    _onFailure = onFailure;
    _onExternalWallet = onExternalWallet;

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleFailure);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handleSuccess(PaymentSuccessResponse response) => _onSuccess?.call(response);
  void _handleFailure(PaymentFailureResponse response) => _onFailure?.call(response);
  void _handleExternalWallet(ExternalWalletResponse response) => _onExternalWallet?.call(response);

  /// Generic one-off checkout used by the Horoscope Analysis (₹399) and the
  /// office-visit appointment (₹50). [amountPaise] is the charge in paise. The
  /// success/failure callbacks wired in [init] drive what happens next.
  void openCheckout({
    required int amountPaise,
    required String description,
    Map<String, String> notes = const {},
    String userPhone = '',
    String userEmail = '',
    String userName = '',
  }) {
    final options = {
      'key': RazorpayConstants.keyId,
      'amount': amountPaise,
      'name': RazorpayConstants.appName,
      'description': description,
      'prefill': {
        'contact': userPhone,
        'email': userEmail,
        'name': userName,
      },
      'notes': notes,
      'theme': {'color': RazorpayConstants.themeColor},
      'currency': RazorpayConstants.currency,
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('RazorpayService.openCheckout error: $e');
    }
  }

  // (openSubscriptionCheckout was removed — there is NO subscription system;
  // only per-booking astrology payments remain.)

  /// Opens the Razorpay checkout for an in-person Horoscope Compatibility Report
  /// appointment. [amountPaise] is the service charge in paise (₹499 → 49900).
  /// The success/failure callbacks wired in [init] drive the booking creation.
  void openAppointmentCheckout({
    required int amountPaise,
    required String userPhone,
    required String userEmail,
    required String userName,
    required String userId,
    String bookingRef = '',
  }) {
    final options = {
      'key': RazorpayConstants.keyId,
      'amount': amountPaise,
      'name': RazorpayConstants.appName,
      'description': 'Horoscope Compatibility Report',
      'prefill': {
        'contact': userPhone,
        'email': userEmail,
        'name': userName,
      },
      'notes': {
        'type': 'horoscope_appointment',
        'userId': userId,
        if (bookingRef.isNotEmpty) 'ref': bookingRef,
      },
      'theme': {'color': RazorpayConstants.themeColor},
      'currency': 'INR',
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('RazorpayService.openAppointmentCheckout error: $e');
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}
