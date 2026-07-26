import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report_model.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// All submitted reports (profile + chat), newest first — feeds the admin
/// Report Management page (spec §8).
final allReportsProvider = StreamProvider.autoDispose<List<ReportModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllReports();
});

/// The signed-in user's OWN submitted reports — feeds the user-facing Reported
/// Users page. Requires the Firestore rule allowing a user to read reports they
/// filed (reporterUserId == uid).
final myReportsProvider = StreamProvider.autoDispose<List<ReportModel>>((ref) {
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const <ReportModel>[]);
  return ref.watch(firestoreServiceProvider).watchMyReports(uid);
});

/// Live count of reports still awaiting review — drives the admin dashboard's
/// "Pending Reports" badge. Derived from [allReportsProvider] so it updates in
/// realtime alongside the list.
final pendingReportsCountProvider = Provider.autoDispose<int>((ref) {
  final reports = ref.watch(allReportsProvider).valueOrNull ?? const [];
  return reports.where((r) => r.status == 'pending').length;
});

/// Admin moderation actions on a report (spec §8).
class ReportAdminController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Set the report's status (warned / rejected / resolved).
  Future<void> setStatus(String reportId, String status) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(firestoreServiceProvider)
        .updateReportStatus(reportId, status));
  }

  /// Suspend the reported user's account (blocks login-gated features and
  /// deactivates their profile) and mark the report 'suspended'.
  Future<void> suspendUser(ReportModel report) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final fs = ref.read(firestoreServiceProvider);
      if (report.reportedUserId.isNotEmpty) {
        await fs.blockUser(report.reportedUserId);
      }
      await fs.updateReportStatus(report.id, 'suspended');
    });
  }

  /// Permanently delete the reported profile and mark the report 'deleted'.
  Future<void> deleteReportedProfile(ReportModel report) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final fs = ref.read(firestoreServiceProvider);
      if (report.reportedProfileId.isNotEmpty) {
        await fs.deleteProfileById(report.reportedProfileId);
      }
      await fs.updateReportStatus(report.id, 'deleted');
    });
  }
}

final reportAdminControllerProvider =
    NotifierProvider<ReportAdminController, AsyncValue<void>>(
        ReportAdminController.new);
