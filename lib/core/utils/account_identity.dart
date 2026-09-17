/// The ACCOUNT POLICY of the app, and the pure rules that enforce and audit it.
///
/// ## The policy
///
///  * **One mobile number → one login account.** `login_index/{mobile}` is the
///    registry: whoever holds that document owns the number for password
///    sign-in. Registration, admin provisioning and the self-healing login
///    write all go through it, and the security rules only let an entry be
///    created by its own uid.
///  * **One login account (Firebase UID) → at most one matrimony profile.**
///    `profile_owners/{uid}` records WHICH profile document the uid owns, and
///    the rules refuse a profile create whose id does not match it. The UID —
///    never the phone number — is what links an account to its profile.
///  * Authentication identities and matrimony profiles stay separate. A
///    second identity for the same person (a Google login, an OTP session) is
///    never turned into a second profile automatically: the admin reviews it
///    in Account Health and links or removes it explicitly.
///
/// ## Why "An account already exists with this phone number" appeared after
/// the login was deleted
///
/// Admin → Delete User removed `profiles` and `users/{uid}` only. It left
/// `login_index/{mobile}` behind — which is exactly what the Create Profile
/// login step checks — and it could not remove the Firebase Authentication
/// record at all (that needs the Admin SDK). The number therefore stayed
/// "registered", pointing at an account that no longer existed in the app, and
/// the old password still signed in and quietly recreated an empty account.
///
/// Everything below is free of Firebase so it can be unit-tested.
library;

import '../../models/profile_model.dart';
import '../../models/user_model.dart';
import 'login_identifier.dart';
import 'profile_completion.dart';

// ── Login access ─────────────────────────────────────────────────────────────

/// Whether an account may still sign in, as recorded on `users/{uid}.authStatus`.
enum LoginAccessState {
  /// Normal account.
  active,

  /// The admin removed the login but KEPT the member's data. The Firebase Auth
  /// record may still exist (Spark plan: it cannot be deleted from the app), so
  /// the app refuses the session instead.
  disabled,

  /// The Firebase Auth record itself was deleted by the trusted backend. The
  /// member's data is kept and the login can be restored under the same UID.
  deleted;

  static LoginAccessState parse(Object? raw) {
    switch ('${raw ?? ''}'.trim().toLowerCase()) {
      case 'disabled':
        return LoginAccessState.disabled;
      case 'deleted':
        return LoginAccessState.deleted;
      default:
        return LoginAccessState.active;
    }
  }

  String get storedValue => name;

  bool get canSignIn => this == LoginAccessState.active;
}

/// `login_tombstones/{uid}` — written by an admin when a login is removed.
///
/// Read by the SIGNING-IN account itself before anything else happens, which
/// is what stops a deleted login from resurrecting its account on the Spark
/// plan, where the Firebase Auth record cannot be deleted from the app.
class LoginTombstone {
  /// `deleted` — the whole account was deleted: the next sign-in with the old
  /// credentials deletes that Firebase Auth record and is refused.
  /// `disabled` — only the login was removed and the data kept: the sign-in is
  /// refused but nothing is deleted, so the admin can restore it.
  static const String modeDeleted = 'deleted';
  static const String modeDisabled = 'disabled';

  final String uid;
  final String mode;
  final String mobile;
  final DateTime? at;

  const LoginTombstone({
    required this.uid,
    required this.mode,
    this.mobile = '',
    this.at,
  });

  bool get deletesAuthRecord => mode == modeDeleted;

  static LoginTombstone? fromMap(String uid, Map<String, dynamic>? data) {
    if (data == null) return null;
    final mode = '${data['mode'] ?? ''}'.trim();
    if (mode != modeDeleted && mode != modeDisabled) return null;
    return LoginTombstone(
      uid: uid,
      mode: mode,
      mobile: '${data['mobile'] ?? ''}'.trim(),
      at: _dateOf(data['at']),
    );
  }
}

// ── Member status (Admin → Users) ───────────────────────────────────────────

/// The five account states the admin panel distinguishes.
enum MemberAccountStatus {
  profileNotCreated('Profile Not Created'),
  profileIncomplete('Profile Incomplete'),
  profileCompleted('Profile Completed'),
  authDeleted('Authentication Account Deleted'),
  needsReview('Duplicate / Unlinked — Needs Review');

  final String label;
  const MemberAccountStatus(this.label);
}

/// Classifies one member for the admin lists.
///
/// [profileCount] is how many non-test profiles are filed under the uid — more
/// than one is always a review case, whatever else is true. [phoneConflict] is
/// set when the account's mobile number is also claimed by another uid.
MemberAccountStatus classifyMemberAccount({
  required UserModel? user,
  required ProfileModel? profile,
  int profileCount = 0,
  bool phoneConflict = false,
}) {
  final count = profileCount > 0 ? profileCount : (profile == null ? 0 : 1);
  if (count > 1 || phoneConflict) return MemberAccountStatus.needsReview;
  if (user != null && !user.loginAccess.canSignIn) {
    return MemberAccountStatus.authDeleted;
  }
  // A profile with no account document is a profile whose login is gone.
  if (user == null && profile != null) return MemberAccountStatus.needsReview;
  if (profile == null) return MemberAccountStatus.profileNotCreated;
  return isProfileCompleteEnough(profile)
      ? MemberAccountStatus.profileCompleted
      : MemberAccountStatus.profileIncomplete;
}

// ── One profile per account ─────────────────────────────────────────────────

/// Which profile document an account's profile is (re)written to.
///
/// [existingNewestFirst] are the profile ids already filed under the uid,
/// [claimedId] is `profile_owners/{uid}.profileId` ('' when there is none) and
/// [freshId] a new auto-id. In order:
///
///  1. the claimed profile, when it exists — the account's one profile;
///  2. otherwise the newest existing profile (legacy data from before the
///     ownership record) — the create REPLACES it instead of adding a second;
///  3. otherwise the claimed id even though no document exists yet — a retry
///     after an interrupted save lands on the same document, never a new one;
///  4. otherwise a fresh id.
String chooseOwnProfileDocId({
  required List<String> existingNewestFirst,
  required String claimedId,
  required String freshId,
}) {
  final claimed = claimedId.trim();
  if (claimed.isNotEmpty && existingNewestFirst.contains(claimed)) return claimed;
  if (existingNewestFirst.isNotEmpty) return existingNewestFirst.first;
  if (claimed.isNotEmpty) return claimed;
  return freshId;
}

// ── Masking (Forgot Password, never reveal more than needed) ─────────────────

/// `98•••••210` — enough for a member to recognise their own number.
String maskMobile(String raw) {
  final m = LoginIdentifier.localMobile(raw) ?? raw.trim();
  if (m.length < 6) return '•' * m.length;
  return '${m.substring(0, 2)}${'•' * (m.length - 5)}${m.substring(m.length - 3)}';
}

/// `ra•••@g•••.com`. A synthesized phone sign-in address is never shown.
String maskEmail(String? raw) {
  final email = LoginIdentifier.realEmailOrEmpty(raw);
  final at = email.indexOf('@');
  if (at <= 0) return '';
  final local = email.substring(0, at);
  final domain = email.substring(at + 1);
  final dot = domain.lastIndexOf('.');
  final host = dot > 0 ? domain.substring(0, dot) : domain;
  final tld = dot > 0 ? domain.substring(dot) : '';
  String part(String s, int keep) =>
      s.length <= keep ? '${s.isEmpty ? '' : s[0]}•••' : '${s.substring(0, keep)}•••';
  return '${part(local, 2)}@${part(host, 1)}$tld';
}

// ── Admin login provisioning: what already holds a mobile number ─────────────

/// What an admin creating a login for a mobile number is actually facing.
enum LoginAvailability {
  /// Nothing holds the number.
  available,

  /// Only a leftover registry entry holds it — its account was deleted. Safe
  /// to release after the admin confirms.
  staleIndex,

  /// A live account already owns the number. Link to it; never create another.
  inUse,

  /// More than one live account claims the number — needs review first.
  multiple,

  /// A Firebase Auth record uses the sign-in address but nothing in the app
  /// belongs to it (backend only). Replaceable after the admin confirms.
  orphanAuth,
}

/// One account found while inspecting a mobile number or a uid.
class ExistingLogin {
  final String uid;
  final String displayName;
  final String mobile;
  final String email;
  final String role;

  /// `users/{uid}` exists.
  final bool hasAccountRecord;

  /// Firebase Auth has a record for the uid — null when unknown (no backend).
  final bool? authExists;

  /// The sign-in address of that record, when the backend reported it.
  final String authEmail;
  final List<String> providers;
  final LoginAccessState access;

  /// `login_tombstones/{uid}.mode`, or ''.
  final String tombstoneMode;
  final int profileCount;
  final String profileId;
  final String profileName;
  final String profileStatus;

  const ExistingLogin({
    required this.uid,
    this.displayName = '',
    this.mobile = '',
    this.email = '',
    this.role = '',
    this.hasAccountRecord = false,
    this.authExists,
    this.authEmail = '',
    this.providers = const [],
    this.access = LoginAccessState.active,
    this.tombstoneMode = '',
    this.profileCount = 0,
    this.profileId = '',
    this.profileName = '',
    this.profileStatus = '',
  });

  /// Still an account in the app: it has its record, was not deleted by an
  /// admin, and (when the backend could check) still has a Firebase login OR
  /// was only disabled with its data kept. A disabled login keeps its number —
  /// the admin can restore it.
  bool get isLive {
    if (!hasAccountRecord) return false;
    if (tombstoneMode == LoginTombstone.modeDeleted) return false;
    if (authExists == false && access == LoginAccessState.active) return false;
    return true;
  }

  String get name =>
      profileName.trim().isNotEmpty ? profileName.trim() : displayName.trim();
}

/// Decides [LoginAvailability]. Pure — see the enum for each outcome.
LoginAvailability decideLoginAvailability({
  required LoginIndexEntry? index,
  required List<ExistingLogin> accounts,
  required bool authChecked,
}) {
  final live = [for (final a in accounts) if (a.isLive) a];
  if (live.length > 1) return LoginAvailability.multiple;
  if (live.length == 1) return LoginAvailability.inUse;
  if (authChecked &&
      accounts.any((a) => a.authExists == true && !a.hasAccountRecord &&
          a.profileCount == 0)) {
    return LoginAvailability.orphanAuth;
  }
  if (index != null) return LoginAvailability.staleIndex;
  return LoginAvailability.available;
}

// ── Account Health scan ─────────────────────────────────────────────────────

/// A `login_index/{mobile}` entry.
class LoginIndexEntry {
  final String mobile;
  final String uid;
  final String authEmail;
  const LoginIndexEntry(
      {required this.mobile, required this.uid, required this.authEmail});
}

/// One Firebase Authentication record, as reported by the trusted backend.
/// The app cannot list Auth users itself, so this is only available once the
/// `adminListAuthAccounts` function is deployed.
class AuthAccountInfo {
  final String uid;
  final String email;
  final String phoneNumber;
  final List<String> providers;
  final bool disabled;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  const AuthAccountInfo({
    required this.uid,
    this.email = '',
    this.phoneNumber = '',
    this.providers = const [],
    this.disabled = false,
    this.createdAt,
    this.lastSignInAt,
  });

  bool get isAnonymous => providers.isEmpty && email.isEmpty && phoneNumber.isEmpty;

  /// Every 10-digit mobile this identity is tied to: its verified phone
  /// provider and/or its synthesized phone sign-in address.
  Set<String> get mobiles => {
        if (LoginIdentifier.localMobile(phoneNumber) != null)
          LoginIdentifier.localMobile(phoneNumber)!,
        if (LoginIdentifier.isPhoneAuthEmail(email))
          email.trim().toLowerCase().substring(1, 11),
      };

  factory AuthAccountInfo.fromMap(Map<String, dynamic> m) => AuthAccountInfo(
        uid: '${m['uid'] ?? ''}',
        email: '${m['email'] ?? ''}',
        phoneNumber: '${m['phoneNumber'] ?? ''}',
        providers: [
          for (final p in (m['providers'] as List? ?? const [])) '$p',
        ],
        disabled: m['disabled'] == true,
        createdAt: _dateOf(m['createdAt']),
        lastSignInAt: _dateOf(m['lastSignInAt']),
      );
}

enum AccountIssueType {
  multipleProfiles('Multiple profiles for one account',
      'One Firebase UID owns more than one matrimony profile.'),
  profileWithoutAccount('Profile without a login account',
      'The profile belongs to a UID whose account record (or Firebase Auth login) no longer exists.'),
  duplicatePhone('Duplicate phone number',
      'The same mobile number is attached to more than one account.'),
  staleLoginIndex('Deleted login still holds a phone number',
      'The mobile → login mapping points at an account that was deleted, so the number looks "already registered".'),
  loginIndexMismatch('Phone login points at the wrong address',
      'The mobile → login mapping does not match the Firebase Auth record of that account.'),
  authWithoutAccount('Unlinked authentication account',
      'A Firebase Auth login exists with no account record in the app.'),
  accountWithoutAuth('Authentication account deleted',
      'The account record exists but its Firebase Auth login does not.'),
  missingOwnershipRecord('Profile ownership not recorded',
      'The one-profile-per-account record is missing or points at the wrong profile (safe to repair).');

  final String title;
  final String description;
  const AccountIssueType(this.title, this.description);
}

/// One inconsistency found by [scanAccountIntegrity]. Nothing is ever changed
/// by the scan itself — every action is a separate, confirmed admin step.
class AccountIssue {
  final AccountIssueType type;

  /// Stable id — used to remember an admin's "reviewed" decision.
  final String key;
  final String mobile;
  final List<String> uids;
  final List<String> profileIds;
  final String detail;

  const AccountIssue({
    required this.type,
    required this.key,
    this.mobile = '',
    this.uids = const [],
    this.profileIds = const [],
    this.detail = '',
  });
}

/// Result of a scan. [authChecked] is false when the backend could not be
/// reached — the Firebase Auth categories are then simply not evaluated, and
/// the page says so instead of reporting them as clean.
class AccountScanReport {
  final List<AccountIssue> issues;
  final bool authChecked;
  final int accounts;
  final int profiles;
  final int authAccounts;

  /// Members (role `user`) who signed up but have no matrimony profile — the
  /// "Profile Not Created" list. Not an inconsistency, but the admin can
  /// create their profile from here.
  final List<String> membersWithoutProfileUids;

  const AccountScanReport({
    required this.issues,
    required this.authChecked,
    required this.accounts,
    required this.profiles,
    required this.authAccounts,
    this.membersWithoutProfileUids = const [],
  });

  int get membersWithoutProfile => membersWithoutProfileUids.length;

  List<AccountIssue> of(AccountIssueType type) =>
      [for (final i in issues) if (i.type == type) i];
}

/// Cross-checks accounts, profiles, the phone registry, the ownership records
/// and (when available) Firebase Auth. Pure — see the library doc for the
/// policy each check enforces.
///
/// Staff, admin and family accounts never own a matrimony profile, so they are
/// not reported as "missing a profile". Test profiles (`isDummy`) are ignored.
AccountScanReport scanAccountIntegrity({
  required List<UserModel> users,
  required List<ProfileModel> profiles,
  required List<LoginIndexEntry> loginIndex,
  required Map<String, String> ownershipClaims,
  Map<String, LoginTombstone> tombstones = const {},
  List<AuthAccountInfo>? authAccounts,
}) {
  final issues = <AccountIssue>[];
  final usersByUid = {for (final u in users) u.uid: u};
  final authByUid = authAccounts == null
      ? null
      : {for (final a in authAccounts) a.uid: a};

  bool accountGone(String uid) {
    if (!usersByUid.containsKey(uid)) return true;
    if (authByUid != null && !authByUid.containsKey(uid)) return true;
    return tombstones[uid]?.deletesAuthRecord ?? false;
  }

  // Profiles per uid.
  final realProfiles = [for (final p in profiles) if (!p.isDummy) p];
  final profilesByUid = <String, List<ProfileModel>>{};
  for (final p in realProfiles) {
    final owner = p.userId.trim();
    if (owner.isEmpty) continue;
    profilesByUid.putIfAbsent(owner, () => []).add(p);
  }

  for (final entry in profilesByUid.entries) {
    final uid = entry.key;
    final list = entry.value;
    if (list.length > 1) {
      issues.add(AccountIssue(
        type: AccountIssueType.multipleProfiles,
        key: 'multi:$uid',
        uids: [uid],
        profileIds: [for (final p in list) p.id],
        detail: '${list.length} profiles: '
            '${list.map((p) => p.fullName.trim().isEmpty ? p.id : p.fullName).join(', ')}',
      ));
    }
    final user = usersByUid[uid];
    final authMissing = authByUid != null && !authByUid.containsKey(uid);
    if (user == null || authMissing) {
      issues.add(AccountIssue(
        type: AccountIssueType.profileWithoutAccount,
        key: 'orphan-profile:$uid',
        mobile: LoginIdentifier.localMobile(user?.phone ?? '') ?? '',
        uids: [uid],
        profileIds: [for (final p in list) p.id],
        detail: user == null
            ? 'No users/$uid account record.'
            : 'users/$uid exists, but Firebase Auth has no login for it.',
      ));
    } else if (list.length == 1 && ownershipClaims[uid] != list.first.id) {
      issues.add(AccountIssue(
        type: AccountIssueType.missingOwnershipRecord,
        key: 'claim:$uid',
        uids: [uid],
        profileIds: [list.first.id],
        detail: ownershipClaims.containsKey(uid)
            ? 'Recorded profile ${ownershipClaims[uid]} does not exist; '
                'the account owns ${list.first.id}.'
            : 'No ownership record for ${list.first.id}.',
      ));
    }
  }

  // Members (role user) without a profile.
  final withoutProfile = <String>[];
  for (final u in users) {
    if (!_isMemberRole(u.role)) continue;
    if (!u.loginAccess.canSignIn) continue;
    if (!profilesByUid.containsKey(u.uid) &&
        !realProfiles.any((p) => p.userId.trim().isEmpty && p.id == u.profileId)) {
      withoutProfile.add(u.uid);
    }
  }

  // Phone ownership: every uid that claims each mobile, from every source.
  final uidsByMobile = <String, Set<String>>{};
  void claim(String? raw, String uid) {
    final m = LoginIdentifier.localMobile(raw ?? '');
    if (m == null || uid.isEmpty) return;
    uidsByMobile.putIfAbsent(m, () => <String>{}).add(uid);
  }

  for (final u in users) {
    if (_isMemberRole(u.role)) claim(u.phone, u.uid);
  }
  for (final e in loginIndex) {
    if (!accountGone(e.uid)) claim(e.mobile, e.uid);
  }
  for (final a in authAccounts ?? const <AuthAccountInfo>[]) {
    for (final m in a.mobiles) {
      claim(m, a.uid);
    }
  }
  for (final entry in uidsByMobile.entries) {
    if (entry.value.length < 2) continue;
    final uids = entry.value.toList()..sort();
    issues.add(AccountIssue(
      type: AccountIssueType.duplicatePhone,
      key: 'phone:${entry.key}',
      mobile: entry.key,
      uids: uids,
      profileIds: [
        for (final uid in uids) ...?profilesByUid[uid]?.map((p) => p.id),
      ],
      detail: '${uids.length} accounts use this number.',
    ));
  }

  // The phone registry itself.
  for (final e in loginIndex) {
    if (e.uid.isEmpty || accountGone(e.uid)) {
      issues.add(AccountIssue(
        type: AccountIssueType.staleLoginIndex,
        key: 'index:${e.mobile}',
        mobile: e.mobile,
        uids: [if (e.uid.isNotEmpty) e.uid],
        detail: tombstones[e.uid]?.deletesAuthRecord == true
            ? 'The login was deleted by an admin.'
            : 'No live account for ${e.uid.isEmpty ? '(empty uid)' : e.uid}.',
      ));
      continue;
    }
    final auth = authByUid?[e.uid];
    if (auth != null &&
        auth.email.trim().toLowerCase() != e.authEmail.trim().toLowerCase()) {
      issues.add(AccountIssue(
        type: AccountIssueType.loginIndexMismatch,
        key: 'index-mismatch:${e.mobile}',
        mobile: e.mobile,
        uids: [e.uid],
        detail: 'Index says ${e.authEmail}; Firebase Auth has '
            '${auth.email.isEmpty ? '(no e-mail credential)' : auth.email}.',
      ));
    }
  }

  // Firebase Auth ↔ account records (backend only).
  if (authAccounts != null) {
    for (final a in authAccounts) {
      if (a.isAnonymous || usersByUid.containsKey(a.uid)) continue;
      issues.add(AccountIssue(
        type: AccountIssueType.authWithoutAccount,
        key: 'auth-orphan:${a.uid}',
        mobile: a.mobiles.isEmpty ? '' : a.mobiles.first,
        uids: [a.uid],
        detail: 'Providers: ${a.providers.isEmpty ? '—' : a.providers.join(', ')}'
            '${a.lastSignInAt == null ? '' : ' · last sign-in ${_d(a.lastSignInAt!)}'}',
      ));
    }
    for (final u in users) {
      if (authByUid!.containsKey(u.uid)) continue;
      if (u.loginAccess == LoginAccessState.deleted) continue; // recorded
      issues.add(AccountIssue(
        type: AccountIssueType.accountWithoutAuth,
        key: 'no-auth:${u.uid}',
        mobile: LoginIdentifier.localMobile(u.phone ?? '') ?? '',
        uids: [u.uid],
        profileIds: [...?profilesByUid[u.uid]?.map((p) => p.id)],
        detail: 'users/${u.uid} has no Firebase Auth login.',
      ));
    }
  }

  return AccountScanReport(
    issues: issues,
    authChecked: authAccounts != null,
    accounts: users.length,
    profiles: realProfiles.length,
    authAccounts: authAccounts?.length ?? 0,
    membersWithoutProfileUids: withoutProfile,
  );
}

/// Staff, admins and family users never own a matrimony profile.
bool _isMemberRole(String role) {
  final r = role.trim().toLowerCase();
  return r.isEmpty || r == 'user';
}

DateTime? _dateOf(Object? v) {
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  try {
    // Firestore Timestamp, without importing cloud_firestore here.
    final d = (v as dynamic)?.toDate();
    return d is DateTime ? d : null;
  } catch (_) {
    return null;
  }
}

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
