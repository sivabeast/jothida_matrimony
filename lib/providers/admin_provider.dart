import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../models/profile_model.dart';
import '../models/report_model.dart';
import '../models/astrologer_account_model.dart';
import '../models/dashboard_analytics.dart';
import '../models/admin_activity.dart';
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

final allUsersProvider = FutureProvider.autoDispose<List<UserModel>>(
    (ref) => ref.read(adminRepositoryProvider).getAllUsers());

/// Recent platform activity for the Dashboard feed (max 5).
final recentActivityProvider = FutureProvider.autoDispose<List<AdminActivity>>(
    (ref) => ref.read(adminRepositoryProvider).getRecentActivity());

final pendingProfilesProvider = FutureProvider.autoDispose<List<ProfileModel>>(
    (ref) => ref.read(adminRepositoryProvider).getPendingProfiles());

final allReportsProvider = FutureProvider.autoDispose<List<ReportModel>>(
    (ref) => ref.read(adminRepositoryProvider).getAllReports());

class AdminActionsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> approveProfile(String profileId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).approveProfile(profileId));
  }

  Future<void> rejectProfile(String profileId, String reason) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).rejectProfile(profileId, reason));
  }

  Future<void> blockUser(String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).blockUser(userId));
  }

  Future<void> unblockUser(String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).unblockUser(userId));
  }

  Future<void> deleteUser(String userId) async {
    debugPrint('[AdminActions] deleteUser($userId)');
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(adminRepositoryProvider).deleteUser(userId));
    if (state.hasError) {
      debugPrint('[AdminActions] ❌ deleteUser failed: ${state.error}');
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
}

final adminActionsProvider =
    NotifierProvider<AdminActionsNotifier, AsyncValue<void>>(() => AdminActionsNotifier());
