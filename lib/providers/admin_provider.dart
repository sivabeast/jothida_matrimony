import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../models/profile_model.dart';
import '../models/report_model.dart';
import 'service_providers.dart';

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
    (ref) => ref.read(adminRepositoryProvider).getAdminStats());

final allUsersProvider = FutureProvider.autoDispose<List<UserModel>>(
    (ref) => ref.read(adminRepositoryProvider).getAllUsers());

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
}

final adminActionsProvider =
    NotifierProvider<AdminActionsNotifier, AsyncValue<void>>(() => AdminActionsNotifier());
