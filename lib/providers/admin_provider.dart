import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../models/profile_model.dart';
import '../models/astrologer_account_model.dart';
import '../models/astrologer_request_model.dart';
import '../models/dashboard_analytics.dart';
import 'auth_provider.dart';
import 'notification_provider.dart';
import 'service_providers.dart';

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.read(adminRepositoryProvider).getAdminStats());

/// Full business-dashboard analytics (revenue, subscriptions, users,
/// astrologers, consultations, marriage). Backed by one Firestore pass.
final dashboardAnalyticsProvider =
    FutureProvider.autoDispose<DashboardAnalytics>(
        (ref) => ref.read(adminRepositoryProvider).getDashboardAnalytics());

/// Live stream of every astrologer account (any status). Used by the admin
/// Astrologer Management / verification screen. Reuses the index-free
/// `watchAllAstrologers` query and groups by status client-side, so it works
/// without any composite Firestore index.
final allAstrologersProvider =
    StreamProvider.autoDispose<List<AstrologerAccount>>((ref) {
  return ref.read(astrologerServiceProvider).watchAllAstrologers();
});

/// Realtime list of every matrimony user (newest first). A StreamProvider, so
/// the admin Users list re-renders the instant a user is added / edited /
/// blocked / deleted — no manual refresh, no stale rows (spec §1-3).
final allUsersProvider = StreamProvider.autoDispose<List<UserModel>>(
    (ref) => ref.read(adminRepositoryProvider).watchAllUsers(limit: 300));

/// LIVE stream of one member's full profile, for the admin User Details page
/// (§6).
///
/// Unlike `profileByUserIdProvider` (a one-shot read restricted to
/// approved + active profiles, so it is safe for member-to-member browsing),
/// this streams the document itself and applies NO status filter — admins can
/// read every profile, including pending / suspended ones. Because it is a
/// snapshot stream, an edit the member makes in the app shows up in the admin
/// panel immediately, with no refresh.
final adminProfileByUserIdProvider =
    StreamProvider.autoDispose.family<ProfileModel?, String>((ref, uid) =>
        ref.read(profileRepositoryProvider).watchProfileByUserId(uid));

/// The member's gated contact record, readable by admins (§6 — "show complete
/// profile information"). Returns null when it hasn't been created yet.
final adminContactByUserIdProvider =
    FutureProvider.autoDispose.family<ContactDetails?, String>((ref, uid) async {
  try {
    return await ref.read(profileRepositoryProvider).getContact(uid);
  } catch (_) {
    return null; // not created yet / rules not deployed — show the rest
  }
});

/// Live stream of every astrologer request (consultations + match-analysis /
/// horoscope bookings). Powers the admin Horoscope Requests page.
final allAstrologerRequestsProvider =
    StreamProvider.autoDispose<List<AstrologerRequestModel>>(
        (ref) => ref.read(astrologerServiceProvider).watchAllRequests());

/// Paid astrology-service transactions — every `astrologer_requests` booking
/// with `paid == true`, newest payment first (`paidAt`, falling back to
/// `createdAt` for older docs). Derived from [allAstrologerRequestsProvider]
/// so the admin Payments page and the Dashboard payment analytics stay
/// realtime; the source stream's loading/error states are preserved.
final paidAstrologerRequestsProvider =
    Provider.autoDispose<AsyncValue<List<AstrologerRequestModel>>>((ref) {
  return ref.watch(allAstrologerRequestsProvider).whenData((list) {
    final paid = list.where((r) => r.paid).toList()
      ..sort((a, b) =>
          (b.paidAt ?? b.createdAt).compareTo(a.paidAt ?? a.createdAt));
    return paid;
  });
});

/// All matrimony profiles (newest first), keyed by [ProfileModel.userId] when
/// joined. Powers the age / district / photo fields on the admin Users cards.
final allProfilesProvider = StreamProvider.autoDispose<List<ProfileModel>>(
    (ref) => ref.read(adminRepositoryProvider).watchAllProfiles());

/// `userId → ProfileModel` lookup for quickly enriching a user row with its
/// matrimony profile (age, district, photo).
final profilesByUserIdProvider =
    FutureProvider.autoDispose<Map<String, ProfileModel>>((ref) async {
  final list = await ref.watch(allProfilesProvider.future);
  return {for (final p in list) p.userId: p};
});

/// Realtime pending-moderation queue (oldest first) — a newly submitted or
/// approved/rejected profile appears / disappears live (spec §1-3).
final pendingProfilesProvider = StreamProvider.autoDispose<List<ProfileModel>>(
    (ref) => ref.read(adminRepositoryProvider).watchPendingProfiles());

/// Live admin activity log (audit trail), newest first.
final adminLogsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => ref.read(firestoreServiceProvider).watchAdminLogs());

/// Aggregate totals too big to stream whole (all users / all notifications):
/// count() queries refreshed every 45s so the dashboard stays near-realtime
/// without an unbounded listener.
final adminAggregateCountsProvider = StreamProvider.autoDispose<
    ({int totalUsers, int totalNotifications})>((ref) async* {
  final svc = ref.read(firestoreServiceProvider);
  while (true) {
    yield await svc.getAdminAggregateCounts();
    await Future.delayed(const Duration(seconds: 45));
  }
});

class AdminActionsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Best-effort append to the `admin_logs` audit trail.
  Future<void> _log(String action,
      {String targetUid = '', String targetProfileId = '', String details = ''}) {
    final adminUid =
        ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
    return ref.read(firestoreServiceProvider).logAdminAction(
          adminUid: adminUid,
          action: action,
          targetUid: targetUid,
          targetProfileId: targetProfileId,
          details: details,
        );
  }

  /// Approves a pending profile. When [userId] is provided the member gets the
  /// "Profile Approved" notification (+ push via the Cloud Function gate).
  Future<void> approveProfile(String profileId, {String userId = ''}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).approveProfile(profileId));
    if (state.hasError) return;
    await _log('profile_approved',
        targetUid: userId, targetProfileId: profileId);
    if (userId.isNotEmpty) {
      await ref.read(notificationNotifierProvider.notifier).notify(
            toUid: userId,
            event: AppNotificationEvent.profileApproved,
            id: 'profile_approved_$profileId',
            // Explicit route so the PUSH tap deep-links too (the in-app feed
            // already falls back to /home for this type; pushes do not).
            route: '/home',
            targetScreen: 'home',
            targetId: profileId,
          );
    }
  }

  Future<void> rejectProfile(String profileId, String reason,
      {String userId = ''}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).rejectProfile(profileId, reason));
    if (state.hasError) return;
    await _log('profile_rejected',
        targetUid: userId, targetProfileId: profileId, details: reason);
  }

  Future<void> blockUser(String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).blockUser(userId));
    if (!state.hasError) await _log('user_suspended', targetUid: userId);
  }

  Future<void> unblockUser(String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).unblockUser(userId));
    if (!state.hasError) await _log('user_activated', targetUid: userId);
  }

  Future<void> deleteUser(String userId) async {
    debugPrint('[AdminActions] deleteUser($userId)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).deleteUser(userId));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ deleteUser failed: ${state.error}');
    } else {
      await _log('user_deleted', targetUid: userId);
    }
  }

  // ── Astrologer verification ────────────────────────────────────────────────
  Future<void> approveAstrologer(String uid) async {
    debugPrint('[AdminActions] approveAstrologer($uid)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(astrologerServiceProvider).approveAstrologer(uid));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ approveAstrologer failed: ${state.error}');
    }
  }

  Future<void> rejectAstrologer(String uid, {String reason = ''}) async {
    debugPrint('[AdminActions] rejectAstrologer($uid, reason="$reason")');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(astrologerServiceProvider).rejectAstrologer(uid, reason: reason));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ rejectAstrologer failed: ${state.error}');
    }
  }

  Future<void> suspendAstrologer(String uid) async {
    debugPrint('[AdminActions] suspendAstrologer($uid)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(astrologerServiceProvider).suspendAstrologer(uid));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ suspendAstrologer failed: ${state.error}');
    }
  }

  /// Permanently deletes an astrologer and ALL their data (account doc,
  /// embedded services/certificates, consultation requests and review
  /// references). No soft-delete — records are physically removed, so the
  /// astrologer disappears from every listing immediately (the directory and
  /// admin screen read live streams).
  Future<void> deleteAstrologer(String uid) async {
    debugPrint('[AdminActions] deleteAstrologer($uid)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(firestoreServiceProvider).deleteAstrologerAccountData(uid));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ deleteAstrologer failed: ${state.error}');
    }
  }

  // ── Horoscope requests ─────────────────────────────────────────────────────
  /// Nudge an astrologer who has not acted on a pending request.
  Future<void> sendRequestReminder(String astrologerId) async {
    debugPrint('[AdminActions] sendRequestReminder($astrologerId)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(astrologerServiceProvider).sendRequestReminder(astrologerId));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ sendRequestReminder failed: ${state.error}');
    }
  }
}

final adminActionsProvider =
    NotifierProvider<AdminActionsNotifier, AsyncValue<void>>(() => AdminActionsNotifier());
