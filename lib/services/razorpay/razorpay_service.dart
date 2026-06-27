import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/razorpay_constants.dart';
import '../../core/constants/app_constants.dart';

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

  void openSubscriptionCheckout({
    required String plan,
    required int amountPaise, // amount in paise (e.g., 9900 for ₹99)
    required String userPhone,
    required String userEmail,
    required String userName,
    required String userId,
  }) {
    final options = {
      'key': RazorpayConstants.testKeyId,
      'amount': amountPaise,
      'name': RazorpayConstants.appName,
      'description': '${_planDisplayName(plan)} Subscription',
      'prefill': {
        'contact': userPhone,
        'email': userEmail,
        'name': userName,
      },
      'notes': {
        'type': 'subscription',
        'plan': plan,
        'userId': userId,
      },
      'theme': {'color': RazorpayConstants.themeColor},
      'currency': 'INR',
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('RazorpayService.openSubscriptionCheckout error: $e');
    }
  }

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

  String _planDisplayName(String plan) {
    switch (plan) {
      case AppConstants.planBasic:
        return 'Basic';
      case AppConstants.planMedium:
        return 'Medium';
      case AppConstants.planPremium:
        return 'Premium';
      default:
        return plan;
    }
  }

  static int planAmountPaise(String plan) {
    switch (plan) {
      case AppConstants.planBasic:
        return AppConstants.basicPrice * 100;
      case AppConstants.planMedium:
        return AppConstants.mediumPrice * 100;
      case AppConstants.planPremium:
        return AppConstants.premiumPrice * 100;
      default:
        return 0;
    }
  }

  void dispose() {
    _razorpay.clear();
  }
}
