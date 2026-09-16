/// The ORDER of a permanent account deletion — pure, so it is unit-tested.
///
/// WHAT WAS WRONG (why "Delete Account" logged the member out, showed "unable
/// to delete", and the same e-mail + password still worked afterwards):
///
///  1. Every Firestore document, chat and uploaded file was deleted FIRST, and
///     only then was the Firebase Auth user deleted.
///  2. That Auth delete needs a RECENT sign-in. When Firebase answered
///     `requires-recent-login` — the normal case for anyone signed in more than
///     a few minutes — the code re-authenticated through GOOGLE ONLY. An
///     e-mail/password (or mobile + password) account can never pass a Google
///     re-authentication, so the Auth account survived.
///  3. The Auth helper then signed out UNCONDITIONALLY, whatever the outcome,
///     and the screen went to Login with an error. Result: data gone, member
///     logged out, and a live login that recreated an empty account next time.
///
/// THE FIXED ORDER
///
///  1. Confirm a signed-in, non-guest user exists. Nothing else happens without
///     one.
///  2. Make sure Firebase WILL allow the Auth delete: if the last sign-in is not
///     recent, re-authenticate with the account's own method (password prompt
///     for password accounts, Google for Google accounts). Cancelled or failed →
///     STOP: nothing deleted, still signed in.
///  3. Delete uploaded files, clear chats, delete the Firestore data, verify.
///     These MUST run while still authenticated: the security rules only let
///     the OWNER delete their documents, and the moment the Auth user is
///     deleted the SDK has no credential left — every delete after that would
///     be refused. (The project is on the Spark plan, so there is no Cloud
///     Function that could clean up after the Auth account is gone.) Step 2 is
///     what makes this safe: the Auth delete is already known to be allowed.
///     If identity data could not be deleted → STOP, still signed in, retryable.
///  4. Delete the Firebase Auth user. `requires-recent-login` → re-authenticate
///     and retry; a network failure → retry. Still failing → STOP, still signed
///     in, and the member is told the login was not deleted. Never a success
///     message, never a sign-out.
///  5. Only after the Auth user is gone: end the session and clear local state.
library;

import '../../repositories/auth_repository.dart'
    show AccountDeletionOutcome, AccountDeletionResult;

/// How a member proves it is them before a sensitive operation.
enum ReauthMethod { password, google, unsupported }

/// Picks the re-authentication method for the account's linked providers.
/// A password credential is preferred when present — it needs no external
/// picker and is the method members of this app log in with.
ReauthMethod reauthMethodForProviders(Iterable<String> providerIds) {
  final ids = providerIds.toSet();
  if (ids.contains('password')) return ReauthMethod.password;
  if (ids.contains('google.com')) return ReauthMethod.google;
  return ReauthMethod.unsupported;
}

/// Firebase allows `user.delete()` only within ~5 minutes of the last
/// sign-in. A slightly shorter window leaves room for the data deletion that
/// runs before the Auth delete.
const Duration kRecentLoginWindow = Duration(minutes: 4);

/// Whether a sign-in at [authTime] is recent enough to delete the Auth user
/// without re-authenticating.
bool isRecentLogin(DateTime? authTime, DateTime now,
    {Duration window = kRecentLoginWindow}) {
  if (authTime == null) return false;
  final age = now.difference(authTime);
  return !age.isNegative && age <= window;
}

/// Deletion steps whose failure must STOP the account deletion before the Auth
/// user is removed: the member's identity, profile, contact and PII records,
/// their login-index entry, and the interests/connections other members see.
/// Once the Auth user is gone nobody but an admin could remove these, so the
/// member is kept signed in to retry instead.
///
/// Everything else (notifications, blocks, legacy booking/consultation records
/// and the retired deletion-request collection) is logged but does not block —
/// none of it identifies the member to anyone.
const Set<String> kBlockingDeletionSteps = {
  'profiles',
  'users',
  'astrologers',
  'contacts',
  'contact_private',
  'profile_private',
  'aadhaar',
  'login_index',
  'interests(sent)',
  'interests(received)',
  'connections',
};

bool blocksAuthDeletion(Iterable<String> failedSteps) =>
    failedSteps.any(kBlockingDeletionSteps.contains);

/// The error codes a re-authentication or an Auth delete can raise that the
/// flow reacts to.
class DeletionAuthError implements Exception {
  final String code;
  final String message;
  const DeletionAuthError(this.code, [this.message = '']);

  bool get requiresRecentLogin => code == 'requires-recent-login';
  bool get isNetwork =>
      code == 'network-request-failed' ||
      code == 'network_error' ||
      code == 'timeout' ||
      code == 'unavailable';

  @override
  String toString() => 'DeletionAuthError($code${message.isEmpty ? '' : ': $message'})';
}

/// Asks the member to re-authenticate with [method]. Returns true once they
/// have, false when they cancelled or could not. Must never sign out.
typedef Reauthenticate = Future<bool> Function(ReauthMethod method);

/// The platform operations the flow drives, injected so the ORDER is tested
/// without Firebase.
class AccountDeletionPorts {
  final String? Function() currentUid;
  final bool Function() isAnonymous;
  final List<String> Function() providerIds;
  final Future<DateTime?> Function() lastSignInTime;

  /// Uploaded files (Cloudinary, legacy Firebase Storage). Best-effort — never
  /// throws.
  final Future<void> Function(String uid) deleteUserFiles;

  /// Removes the member from shared chat threads. Best-effort.
  final Future<void> Function(String uid) clearChats;

  /// Deletes the Firestore data; returns the names of steps that failed.
  final Future<List<String>> Function(String uid) deleteUserData;

  /// Whether the profile or account document can still be read.
  final Future<bool> Function(String uid) hasResidualData;

  /// Deletes the Firebase Auth user. Throws [DeletionAuthError]. Must NOT sign
  /// out.
  final Future<void> Function() deleteAuthUser;

  /// Signs out and clears local session state. Runs only after the Auth user
  /// is gone.
  final Future<void> Function() endSession;

  /// Waits between retries (injectable so tests do not sleep).
  final Future<void> Function(Duration) wait;

  const AccountDeletionPorts({
    required this.currentUid,
    required this.isAnonymous,
    required this.providerIds,
    required this.lastSignInTime,
    required this.deleteUserFiles,
    required this.clearChats,
    required this.deleteUserData,
    required this.hasResidualData,
    required this.deleteAuthUser,
    required this.endSession,
    this.wait = Future<void>.delayed,
  });
}

class AccountDeletionFlow {
  final AccountDeletionPorts ports;
  final DateTime Function() now;
  final void Function(String message) log;

  /// Auth-delete attempts, including retries after re-authentication or a
  /// network error.
  static const int maxAuthAttempts = 3;

  AccountDeletionFlow(this.ports,
      {DateTime Function()? now, void Function(String)? log})
      : now = now ?? DateTime.now,
        log = log ?? ((_) {});

  Future<AccountDeletionResult> run(Reauthenticate reauthenticate) async {
    // 1. A real, signed-in account.
    final uid = ports.currentUid();
    if (uid == null || uid.isEmpty || ports.isAnonymous()) {
      log('no signed-in account — nothing deleted');
      return const AccountDeletionResult.stopped(
          AccountDeletionOutcome.notSignedIn);
    }
    final method = reauthMethodForProviders(ports.providerIds());

    // 2. Make the Auth delete allowed BEFORE anything is removed.
    DateTime? signedInAt;
    try {
      signedInAt = await ports.lastSignInTime();
    } catch (e) {
      log('last sign-in time unavailable ($e) — re-authentication required');
    }
    if (!isRecentLogin(signedInAt, now())) {
      if (method == ReauthMethod.unsupported) {
        log('re-authentication needed but no supported method '
            '(providers=${ports.providerIds()}) — nothing deleted');
        return const AccountDeletionResult.stopped(
            AccountDeletionOutcome.reauthUnsupported);
      }
      log('last sign-in not recent — re-authenticating with $method');
      if (!await reauthenticate(method)) {
        log('re-authentication cancelled/failed — nothing deleted, still '
            'signed in');
        return const AccountDeletionResult.stopped(
            AccountDeletionOutcome.cancelled);
      }
    }

    // 3. Files, chats and Firestore data — while still authenticated.
    await ports.deleteUserFiles(uid);
    await ports.clearChats(uid);
    final failedSteps = await ports.deleteUserData(uid);
    final residual = await ports.hasResidualData(uid);
    if (blocksAuthDeletion(failedSteps) || residual) {
      log('data deletion incomplete (failed=$failedSteps, residual=$residual) '
          '— Auth user kept, still signed in, retryable');
      return AccountDeletionResult(
        authDeleted: false,
        failedSteps: failedSteps,
        residualData: residual,
        outcome: AccountDeletionOutcome.dataNotDeleted,
      );
    }
    if (failedSteps.isNotEmpty) {
      log('non-identifying cleanup incomplete (logged, not blocking): '
          '$failedSteps');
    }

    // 4. The Firebase Auth user itself.
    var authDeleted = false;
    for (var attempt = 1; attempt <= maxAuthAttempts; attempt++) {
      try {
        await ports.deleteAuthUser();
        authDeleted = true;
        log('Firebase Auth user deleted (attempt $attempt)');
        break;
      } on DeletionAuthError catch (e) {
        log('Auth delete attempt $attempt failed: $e');
        if (attempt == maxAuthAttempts) break;
        if (e.requiresRecentLogin) {
          if (method == ReauthMethod.unsupported ||
              !await reauthenticate(method)) {
            break;
          }
        } else if (e.isNetwork) {
          await ports.wait(Duration(seconds: attempt));
        } else {
          break;
        }
      }
    }
    if (!authDeleted) {
      return AccountDeletionResult(
        authDeleted: false,
        failedSteps: failedSteps,
        outcome: AccountDeletionOutcome.loginNotDeleted,
      );
    }

    // 5. Only now: end the session and clear local state.
    try {
      await ports.endSession();
    } catch (e) {
      log('post-deletion session cleanup incomplete: $e');
    }
    return AccountDeletionResult(
      authDeleted: true,
      failedSteps: failedSteps,
      outcome: AccountDeletionOutcome.deleted,
    );
  }
}
