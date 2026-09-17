import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/account_identity.dart';

/// A failure from the account backend (functions/accounts.js).
///
/// [reason] is the machine-readable `details.reason` the functions attach —
/// `phone-number-already-exists`, `email-already-in-use`, `orphan-auth-account`,
/// `user-not-found`, `no-password-login`, `otp-expired`, `otp-already-used`,
/// `multiple-profiles`, `select-account`, `no-account` … — so the app can say
/// what actually happened instead of a generic "already exists".
class AccountBackendException implements Exception {
  final String code;
  final String reason;
  final String message;
  final Map<String, dynamic> details;

  const AccountBackendException(this.code, this.message,
      {this.reason = '', this.details = const {}});

  /// The backend is not deployed (Spark plan) or could not be reached. Callers
  /// fall back to what the app can do on its own instead of failing hard.
  bool get isUnavailable =>
      code == 'not-deployed' || code == 'unavailable' || code == 'network';

  /// The account a conflict refers to, when the backend described it.
  BackendAccount? get account {
    final raw = details['account'];
    return raw is Map ? BackendAccount.fromMap(Map<String, dynamic>.from(raw)) : null;
  }

  @override
  String toString() => message;
}

/// One account as described by `adminInspectLogin` — the Firebase Auth record
/// (null when it no longer exists) plus what the app holds for that uid.
class BackendAccount {
  final String uid;
  final AuthAccountInfo? auth;
  final bool hasUserDoc;
  final String displayName;
  final String phone;
  final String email;
  final String role;
  final LoginAccessState access;
  final String tombstoneMode;
  final int profileCount;
  final String profileId;
  final String profileName;
  final String profileStatus;

  const BackendAccount({
    required this.uid,
    this.auth,
    this.hasUserDoc = false,
    this.displayName = '',
    this.phone = '',
    this.email = '',
    this.role = '',
    this.access = LoginAccessState.active,
    this.tombstoneMode = '',
    this.profileCount = 0,
    this.profileId = '',
    this.profileName = '',
    this.profileStatus = '',
  });

  factory BackendAccount.fromMap(Map<String, dynamic> m) => BackendAccount(
        uid: '${m['uid'] ?? ''}',
        auth: m['auth'] is Map
            ? AuthAccountInfo.fromMap(Map<String, dynamic>.from(m['auth']))
            : null,
        hasUserDoc: m['hasUserDoc'] == true,
        displayName: '${m['displayName'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        email: '${m['email'] ?? ''}',
        role: '${m['role'] ?? ''}',
        access: LoginAccessState.parse(m['authStatus']),
        tombstoneMode: '${m['tombstoneMode'] ?? ''}',
        profileCount: (m['profileCount'] as num?)?.toInt() ?? 0,
        profileId: '${m['profileId'] ?? ''}',
        profileName: '${m['profileName'] ?? ''}',
        profileStatus: '${m['profileStatus'] ?? ''}',
      );
}

/// Recovery lookup result: which account(s) an OTP-verified number may reset.
class RecoveryAccounts {
  /// `single` or `select`.
  final String status;
  final List<RecoveryAccountOption> accounts;
  const RecoveryAccounts(this.status, this.accounts);
}

class RecoveryAccountOption {
  final String ref;
  final String label;
  final String name;
  final bool hasProfile;
  const RecoveryAccountOption(
      {required this.ref,
      required this.label,
      required this.name,
      required this.hasProfile});
}

/// Client for the trusted account backend (Cloud Functions, Blaze plan).
///
/// Uses the `cloud_functions` plugin so the Firebase ID token AND the App Check
/// token travel with every call — the functions enforce both.
class AccountAdminBackend {
  final FirebaseFunctions _functions;

  AccountAdminBackend({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Remembers "not deployed" briefly so a screen does not wait on a round trip
  /// for every button. Cleared after [_unavailableTtl].
  static DateTime? _unavailableSince;
  static const _unavailableTtl = Duration(minutes: 5);

  static bool get knownUnavailable {
    final since = _unavailableSince;
    return since != null &&
        DateTime.now().difference(since) < _unavailableTtl;
  }

  @visibleForTesting
  static void resetAvailability() => _unavailableSince = null;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data, {
    bool limitedUseToken = false,
  }) async {
    if (knownUnavailable) {
      throw const AccountBackendException('not-deployed',
          'The account backend is not deployed on this Firebase project.');
    }
    try {
      final result = await _functions
          .httpsCallable(name,
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 45),
                limitedUseAppCheckToken: limitedUseToken,
              ))
          .call<Object?>(data);
      _unavailableSince = null;
      final raw = result.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final mapped = mapFunctionsError(e.code, e.message, e.details);
      if (mapped.code == 'not-deployed') _unavailableSince = DateTime.now();
      debugPrint('[AccountBackend] $name → ${mapped.code}'
          '${mapped.reason.isEmpty ? '' : '/${mapped.reason}'}: ${mapped.message}');
      throw mapped;
    } on TimeoutException {
      throw const AccountBackendException(
          'unavailable', 'The server did not respond in time.');
    } catch (e) {
      debugPrint('[AccountBackend] $name transport error: $e');
      throw AccountBackendException('network', 'Could not reach the server. ($e)');
    }
  }

  /// Maps a callable failure. A function that does not exist answers
  /// `NOT_FOUND` with no details; our functions never use `not-found`
  /// themselves, so that combination means "not deployed".
  @visibleForTesting
  static AccountBackendException mapFunctionsError(
      String code, String? message, Object? details) {
    final d = details is Map ? Map<String, dynamic>.from(details) : <String, dynamic>{};
    final c = code.toLowerCase();
    if (c == 'not-found' && d.isEmpty) {
      return const AccountBackendException('not-deployed',
          'The account backend is not deployed on this Firebase project.');
    }
    if (c == 'unavailable' || c == 'deadline-exceeded') {
      return AccountBackendException('unavailable',
          message ?? 'The server is unavailable right now.');
    }
    return AccountBackendException(c, message ?? 'The request failed.',
        reason: '${d['reason'] ?? ''}', details: d);
  }

  // ── Admin ───────────────────────────────────────────────────────────────

  Future<({LoginIndexEntry? index, List<BackendAccount> accounts})> inspectLogin(
      {String mobile = '', String email = '', String uid = ''}) async {
    final r = await _call('adminInspectLogin',
        {'mobile': mobile, 'email': email, 'uid': uid});
    final idx = r['index'];
    return (
      index: idx is Map
          ? LoginIndexEntry(
              mobile: '${r['mobile'] ?? mobile}',
              uid: '${idx['uid'] ?? ''}',
              authEmail: '${idx['authEmail'] ?? ''}')
          : null,
      accounts: [
        for (final a in (r['accounts'] as List? ?? const []))
          if (a is Map) BackendAccount.fromMap(Map<String, dynamic>.from(a)),
      ],
    );
  }

  Future<Map<String, dynamic>> provisionLogin({
    required String mobile,
    required String email,
    required String password,
    String displayName = '',
    String gender = '',
    String targetUid = '',
    String replaceOrphanUid = '',
    bool profileCreated = false,
    bool mustChangePassword = false,
  }) =>
      _call('adminProvisionLogin', {
        'mobile': mobile,
        'email': email,
        'password': password,
        'displayName': displayName,
        'gender': gender,
        'targetUid': targetUid,
        'replaceOrphanUid': replaceOrphanUid,
        'profileCreated': profileCreated,
        'mustChangePassword': mustChangePassword,
      });

  Future<({bool authDeleted, int indexRemoved})> deleteLogin(String uid,
      {required bool keepData}) async {
    final r = await _call('adminDeleteLogin', {'uid': uid, 'keepData': keepData});
    return (
      authDeleted: r['authDeleted'] == true,
      indexRemoved: (r['indexRemoved'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> setTemporaryPassword(String uid, {String requestId = ''}) async {
    final r = await _call(
        'adminSetTemporaryPassword', {'uid': uid, 'requestId': requestId});
    return '${r['temporaryPassword'] ?? ''}';
  }

  /// Every Firebase Auth record, paged by the backend (capped for safety).
  Future<List<AuthAccountInfo>> listAuthAccounts({int maxPages = 20}) async {
    final all = <AuthAccountInfo>[];
    var token = '';
    for (var page = 0; page < maxPages; page++) {
      final r = await _call('adminListAuthAccounts',
          {if (token.isNotEmpty) 'pageToken': token});
      for (final a in (r['accounts'] as List? ?? const [])) {
        if (a is Map) all.add(AuthAccountInfo.fromMap(Map<String, dynamic>.from(a)));
      }
      token = '${r['nextPageToken'] ?? ''}';
      if (token.isEmpty) break;
    }
    return all;
  }

  // ── Member recovery (called from an OTP-verified phone session) ──────────

  Future<RecoveryAccounts> recoveryLookup(String mobile) async {
    final r = await _call('resetPasswordWithPhone',
        {'mobile': mobile, 'lookupOnly': true},
        limitedUseToken: true);
    return RecoveryAccounts('${r['status'] ?? 'single'}', [
      for (final a in (r['accounts'] as List? ?? const []))
        if (a is Map)
          RecoveryAccountOption(
            ref: '${a['ref'] ?? ''}',
            label: '${a['label'] ?? ''}',
            name: '${a['name'] ?? ''}',
            hasProfile: a['hasProfile'] == true,
          ),
    ]);
  }

  Future<void> resetPasswordWithOtp({
    required String mobile,
    required String newPassword,
    String accountRef = '',
  }) =>
      _call(
          'resetPasswordWithPhone',
          {
            'mobile': mobile,
            'newPassword': newPassword,
            if (accountRef.isNotEmpty) 'accountRef': accountRef,
          },
          limitedUseToken: true);
}
