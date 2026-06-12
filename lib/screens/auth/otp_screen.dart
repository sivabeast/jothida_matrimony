import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../core/errors/auth_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/auth_routing.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/gradient_button.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String verificationId;
  final String phone;

  const OtpScreen({
    super.key,
    required this.verificationId,
    required this.phone,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _otp = '';
  int _secondsLeft = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) _canResend = true;
      });
      return _secondsLeft > 0;
    });
  }

  Future<void> _verify() async {
    if (_otp.length != 6) return;
    debugPrint('[OtpScreen] "Verify OTP" tapped (otp length=${_otp.length}).');
    await ref
        .read(authNotifierProvider.notifier)
        .signInWithOTP(widget.verificationId, _otp);

    final auth = ref.read(authNotifierProvider);
    if (!mounted) return;
    if (auth.hasError) {
      final err = auth.error;
      final message = err is AuthException
          ? err.message
          : 'OTP verification failed. Please check the code and try again.';
      debugPrint('[OtpScreen] signInWithOTP error: $err');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } else if (auth.valueOrNull != null) {
      final user = auth.valueOrNull!;
      debugPrint('[OtpScreen] OTP verified (uid=${user.uid}, '
          'isProfileComplete=${user.isProfileComplete}). Routing...');
      await routeAuthenticatedUser(context, ref, user, tag: 'OtpScreen');
    }
  }

  Future<void> _resend() async {
    setState(() {
      _secondsLeft = 60;
      _canResend = false;
    });
    await ref.read(otpNotifierProvider.notifier).sendOtp(widget.phone);
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify OTP'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Image.asset(
              'assets/images/app_logo.png',
              width: 90,
              height: 90,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.sms, color: AppColors.primary, size: 40),
              ),
            ),
            const SizedBox(height: 24),
            Text('Enter OTP', style: AppTextStyles.heading2),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit code to +91 ${widget.phone}',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PinCodeTextField(
              appContext: context,
              length: 6,
              onChanged: (val) => setState(() => _otp = val),
              onCompleted: (_) => _verify(),
              keyboardType: TextInputType.number,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(8),
                fieldHeight: 56,
                fieldWidth: 48,
                activeFillColor: Colors.white,
                inactiveFillColor: Colors.grey[100]!,
                selectedFillColor: AppColors.primary.withOpacity(0.05),
                activeColor: AppColors.primary,
                selectedColor: AppColors.primary,
                inactiveColor: Colors.grey[300]!,
              ),
              enableActiveFill: true,
            ),
            const SizedBox(height: 24),
            GradientButton(
              onPressed: (_otp.length == 6 && !authAsync.isLoading) ? _verify : null,
              isLoading: authAsync.isLoading,
              text: 'Verify OTP',
            ),
            const SizedBox(height: 20),
            if (_canResend)
              TextButton(
                onPressed: _resend,
                child: const Text('Resend OTP'),
              )
            else
              Text(
                'Resend in $_secondsLeft seconds',
                style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
