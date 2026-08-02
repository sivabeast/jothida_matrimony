import 'phone_utils.dart';

/// What the user typed into the single "Phone Number or Email" login field.
enum LoginIdentifierKind {
  /// A 10-digit Indian mobile number (with or without +91 / spaces / dashes).
  phone,

  /// Anything shaped like an e-mail address.
  email,

  /// Neither — the form refuses to submit.
  unknown,
}

/// Helpers for the TWO password login identifiers the app supports:
/// **mobile number** and **e-mail address**. Usernames were removed entirely —
/// there is no third form.
///
/// Firebase Authentication can only verify a password against an *e-mail*
/// credential, so every password account is created with one. Which address
/// that is depends on what the member has:
///
///  • a real e-mail  → the account uses that address, and e-mail login is a
///    direct `signInWithEmailAndPassword` with no lookup at all;
///  • no e-mail (very common for admin-created profiles) → the account uses a
///    deterministic, non-deliverable address derived from the mobile number
///    ([phoneAuthEmail]), so phone login is *also* a direct sign-in.
///
/// A phone number therefore only needs a directory lookup
/// ([LoginDirectoryService]) when the member registered with a real e-mail; the
/// synthesized address is the fallback and always works for phone-only
/// accounts, even offline-first.
class LoginIdentifier {
  const LoginIdentifier._();

  /// Domain of the synthesized, non-deliverable address used when an account
  /// has no real e-mail. It is intentionally NOT a real mail domain: nothing is
  /// ever sent to it, it only carries the Firebase password credential.
  static const String phoneEmailDomain = 'phone.jothidamatrimony.app';

  static final RegExp _emailRe =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  /// Classifies a raw login identifier. Phone is tested first so a number typed
  /// with spaces/`+91` is never mistaken for anything else.
  static LoginIdentifierKind kindOf(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return LoginIdentifierKind.unknown;
    if (localMobile(value) != null) return LoginIdentifierKind.phone;
    if (_emailRe.hasMatch(value)) return LoginIdentifierKind.email;
    return LoginIdentifierKind.unknown;
  }

  /// The plain 10-digit local mobile number in [raw], or `null` when [raw] is
  /// not a mobile number. Accepts `9876543210`, `+91 98765 43210`,
  /// `091-9876543210`, … via [normalizeIndianPhone].
  static String? localMobile(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    // An '@' can never be part of a phone number — bail out early so an e-mail
    // whose local part is all digits (e.g. 9876543210@gmail.com) is never
    // treated as a mobile number.
    if (value.contains('@')) return null;
    final normalized = normalizeIndianPhone(value);
    if (normalized.length == 12 && normalized.startsWith('91')) {
      return normalized.substring(2);
    }
    return null;
  }

  /// The deterministic Firebase Auth address for a phone-only account.
  /// Always derived from the 10-digit local number, so it is stable forever.
  static String phoneAuthEmail(String mobile) {
    final local = localMobile(mobile) ?? mobile.trim();
    return 'p$local@$phoneEmailDomain';
  }

  /// True when [email] is one of our synthesized phone addresses rather than a
  /// real inbox. Used to avoid showing (or mailing) it to anyone.
  static bool isPhoneAuthEmail(String? email) =>
      (email ?? '').trim().toLowerCase().endsWith('@$phoneEmailDomain');

  /// A real, user-visible e-mail address or `''` — never a synthesized one.
  static String realEmailOrEmpty(String? email) {
    final value = (email ?? '').trim();
    if (value.isEmpty || isPhoneAuthEmail(value)) return '';
    return value;
  }

  /// Firestore document id used to index a mobile number in `login_index`.
  static String phoneKey(String mobile) => localMobile(mobile) ?? mobile.trim();
}
