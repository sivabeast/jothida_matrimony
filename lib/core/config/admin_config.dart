/// Configuration for privileged (Super Admin) access.
///
/// The email addresses listed here are automatically granted the
/// `super_admin` role on login (see
/// `FirestoreService.createOrUpdateUserOnLogin`). Comparison is
/// case-insensitive and trimmed. To grant another super admin, add their
/// Gmail address to [superAdminEmails] — no other change is required.
class AdminConfig {
  AdminConfig._();

  /// Whitelisted Super Admin accounts. ONLY these emails receive the
  /// `super_admin` role (automatically, on login).
  static const List<String> superAdminEmails = <String>[
    'sivabeast123123@gmail.com',
  ];

  static const String roleSuperAdmin = 'super_admin';
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';

  /// True when [email] is one of the configured Super Admin accounts.
  static bool isSuperAdminEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final normalized = email.trim().toLowerCase();
    return superAdminEmails.any((e) => e.toLowerCase() == normalized);
  }

  /// Role that should be assigned to a freshly-created user document.
  static String roleForEmail(String? email) =>
      isSuperAdminEmail(email) ? roleSuperAdmin : roleUser;
}
