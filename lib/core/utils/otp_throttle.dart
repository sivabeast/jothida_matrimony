import 'package:shared_preferences/shared_preferences.dart';

/// Client-side abuse limits for password-recovery OTPs.
///
/// These are the FIRST line only. Firebase Phone Auth enforces its own
/// per-number and per-device SMS quotas (plus Play Integrity / reCAPTCHA), and
/// the `resetPasswordWithPhone` backend rate-limits lookups and resets per
/// number and refuses a reused or expired verification. This class keeps the
/// app itself from hammering any of them and gives the member a countdown
/// instead of an opaque "too many requests".
class OtpThrottle {
  const OtpThrottle._();

  /// Minimum gap between two sends to the same number.
  static const Duration resendCooldown = Duration(seconds: 60);

  /// At most [maxSendsPerWindow] sends per number in any [window].
  static const int maxSendsPerWindow = 3;
  static const Duration window = Duration(minutes: 30);

  /// Wrong codes allowed for one sent OTP before a new one must be requested.
  static const int maxWrongCodes = 5;

  /// How long the member must wait before another OTP may be sent, given the
  /// times OTPs were previously sent to this number. [Duration.zero] = now.
  static Duration waitBeforeSend(List<DateTime> previousSends, DateTime now) {
    final recent = [
      for (final t in previousSends)
        if (now.difference(t) < window && !t.isAfter(now)) t,
    ]..sort();
    if (recent.length >= maxSendsPerWindow) {
      final opensAt = recent[recent.length - maxSendsPerWindow].add(window);
      final wait = opensAt.difference(now);
      if (wait > Duration.zero) return wait;
    }
    if (recent.isNotEmpty) {
      final sinceLast = now.difference(recent.last);
      if (sinceLast < resendCooldown) return resendCooldown - sinceLast;
    }
    return Duration.zero;
  }

  /// Whether a wait is the long "too many requests" kind rather than the
  /// ordinary resend countdown.
  static bool isLockout(Duration wait) => wait > resendCooldown;

  static String _key(String mobile) => 'otp_recovery_sends_$mobile';

  /// Previous sends to [mobile] on this device (pruned to [window]).
  static Future<List<DateTime>> loadSends(String mobile, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = now ?? DateTime.now();
      return [
        for (final raw in prefs.getStringList(_key(mobile)) ?? const <String>[])
          if (int.tryParse(raw) != null)
            DateTime.fromMillisecondsSinceEpoch(int.parse(raw)),
      ].where((t) => at.difference(t) < window).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> recordSend(String mobile, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = now ?? DateTime.now();
      final sends = [...await loadSends(mobile, now: at), at];
      await prefs.setStringList(_key(mobile),
          [for (final t in sends) '${t.millisecondsSinceEpoch}']);
    } catch (_) {
      // Best-effort — the server-side limits still apply.
    }
  }
}
