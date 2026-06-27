/// The synthetic astrologer id every Match Analysis request is addressed to.
///
/// The app no longer has multiple astrologers — there is ONE internal astrology
/// service owned by the application owner. All match-analysis requests carry
/// this constant as their `astrologerId`, and the internal Astrology Dashboard
/// (only reachable by [AdminConfig.internalAstrologyEmail]) streams every
/// request addressed to it. It is intentionally NOT a real user uid.
const String kInternalAstrologyId = 'internal_astrology';

/// Display name shown on internal match-analysis requests / reports.
const String kInternalAstrologyName = 'Astrology Service';

/// Configuration for privileged (Super Admin) and internal-service access.
///
/// The email addresses listed here are automatically granted the
/// `super_admin` role on login (see
/// `FirestoreService.createOrUpdateUserOnLogin`). Comparison is
/// case-insensitive and trimmed. To grant another super admin, add their
/// Gmail address to [superAdminEmails] — no other change is required.
class AdminConfig {
  AdminConfig._();

  /// Whitelisted Super Admin accounts. ONLY these emails receive the
  /// `super_admin` role (automatically, on login). This account behaves like a
  /// normal matrimony user but also sees the Admin + Astrology dashboard
  /// shortcuts in the Home header.
  static const List<String> superAdminEmails = <String>[
    'sivabeast123123@gmail.com',
  ];

  /// The dedicated INTERNAL astrology/admin account. This Gmail skips the whole
  /// matrimony experience (no onboarding, home, matches or profile) and lands
  /// directly on the lightweight Astrology Dashboard. It is the only account
  /// that owns and manages the internal Match Analysis service.
  static const String internalAstrologyEmail = 'sivasanmuganathan2005@gmail.com';

  static const String roleSuperAdmin = 'super_admin';
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';

  /// True when [email] is one of the configured Super Admin accounts.
  static bool isSuperAdminEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final normalized = email.trim().toLowerCase();
    return superAdminEmails.any((e) => e.toLowerCase() == normalized);
  }

  /// True when [email] is the dedicated internal astrology account.
  static bool isInternalAstrologyEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    return email.trim().toLowerCase() == internalAstrologyEmail.toLowerCase();
  }

  /// Role that should be assigned to a freshly-created user document.
  static String roleForEmail(String? email) =>
      isSuperAdminEmail(email) ? roleSuperAdmin : roleUser;
}
