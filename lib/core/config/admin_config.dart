/// The synthetic addressee id carried by appointment / match-analysis request
/// documents (`astrologerId`). It is a plain DATA constant — intentionally NOT
/// a real user uid and NOT tied to any account or permission. The admin panel
/// queries on it to list the official consultation service's bookings.
const String kInternalAstrologyId = 'internal_astrology';

/// Display name shown on those requests / reports.
const String kInternalAstrologyName = 'Astrology Service';

/// Configuration for privileged (Super Admin) access.
///
/// The email addresses listed here are automatically granted the
/// `super_admin` role on login (see
/// `FirestoreService.createOrUpdateUserOnLogin`). Comparison is
/// case-insensitive and trimmed. To grant another super admin, add their
/// Gmail address to [superAdminEmails] — no other change is required.
///
/// NOTE: there is NO email-based astrology access anymore — the old internal
/// astrology account and its Astrology Dashboard were removed. Horoscope
/// reports are handled by admin-provisioned EMPLOYEES (the astrology_team
/// registry), detected at login by registry lookup, never by hardcoded email.
class AdminConfig {
  AdminConfig._();

  /// Whitelisted Super Admin accounts. ONLY these emails receive the
  /// `super_admin` role (automatically, on login). This account behaves like a
  /// normal matrimony user but also sees the Admin shortcut in the Home header.
  static const List<String> superAdminEmails = <String>[
    'sivabeast123123@gmail.com',
  ];

  /// DEDICATED ADMIN accounts (§2).
  ///
  /// Unlike a super admin — which is a normal matrimony member that also gets
  /// an Admin shortcut — these accounts are admin-ONLY:
  ///
  ///  • they land on the Admin Dashboard and nothing else,
  ///  • the router confines them to `/admin` routes, so the user Home, the
  ///    user navigation and every other user-side page are unreachable,
  ///  • onboarding never runs, so NO `profiles/{id}` document is ever created
  ///    for them.
  ///
  /// The account still gets a `users/{uid}` record holding `role: 'admin'` —
  /// that record IS the admin credential (`firestore.rules` resolves
  /// `isAdmin()` by reading it), so without it the account could not read or
  /// write anything in the admin panel. It carries no matrimony profile data.
  static const List<String> dedicatedAdminEmails = <String>[
    'sathiyaraj887084@gmail.com',
  ];

  static const String roleSuperAdmin = 'super_admin';
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';

  /// True when [email] is one of the configured Super Admin accounts.
  static bool isSuperAdminEmail(String? email) =>
      _matches(email, superAdminEmails);

  /// True when [email] is a DEDICATED admin account (admin panel only).
  static bool isDedicatedAdminEmail(String? email) =>
      _matches(email, dedicatedAdminEmails);

  /// True for any account that is privileged in some way — used where the two
  /// kinds must both be excluded (e.g. the employee-registry auto-detection).
  static bool isPrivilegedEmail(String? email) =>
      isSuperAdminEmail(email) || isDedicatedAdminEmail(email);

  static bool _matches(String? email, List<String> list) {
    if (email == null || email.trim().isEmpty) return false;
    final normalized = email.trim().toLowerCase();
    return list.any((e) => e.toLowerCase() == normalized);
  }

  /// Role that should be assigned to a freshly-created user document.
  static String roleForEmail(String? email) {
    if (isDedicatedAdminEmail(email)) return roleAdmin;
    if (isSuperAdminEmail(email)) return roleSuperAdmin;
    return roleUser;
  }
}
