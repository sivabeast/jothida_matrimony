import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/astrologer_account_model.dart';
import '../models/astrologer_request_model.dart';
import 'admin_provider.dart';
import 'appointment_provider.dart';
import 'auth_provider.dart';
import 'report_provider.dart';

/// Admin drawer notification badges (spec §20–§26).
///
/// A badge counts **new, action-required** records only — never the total in
/// the collection. "New" means: the record still needs the admin to do
/// something (pending verification / pending booking / pending report request
/// / unreviewed user report) **and** it arrived after the admin last opened
/// that section.
///
/// Opening the section marks it seen, so the badge clears while every record
/// stays exactly where it was — clearing a notification never deletes data
/// (spec §26). The seen marks are per admin account, stored on the device.

/// The admin drawer routes that carry a badge. The route string is the key, so
/// a drawer item and its badge can never drift apart.
class AdminBadgeSection {
  static const pendingVerification = '/admin/approvals';
  static const appointments = '/admin/appointments';
  static const horoscopeRequests = '/admin/horoscope-requests';
  static const userReports = '/admin/reports';
  static const employees = '/admin/astrologers';

  static const all = <String>[
    pendingVerification,
    appointments,
    horoscopeRequests,
    userReports,
    employees,
  ];
}

/// `route → millisecondsSinceEpoch` of the last time the admin opened it.
///
/// Defaults to 0 for a section that has never been opened, so a genuine
/// backlog of pending work is surfaced rather than silently swallowed.
class AdminSeenNotifier extends Notifier<Map<String, int>> {
  static const _prefix = 'admin_seen_';

  @override
  Map<String, int> build() {
    _load();
    return const {};
  }

  String get _uid => ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';

  String _key(String route) => '$_prefix${_uid}_$route';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, int>{};
    for (final route in AdminBadgeSection.all) {
      final v = prefs.getInt(_key(route));
      if (v != null) out[route] = v;
    }
    state = out;
  }

  /// Marks [route] seen as of now — called when the admin opens that page.
  Future<void> markSeen(String route) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (state[route] == now) return;
    state = {...state, route: now};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(route), now);
  }
}

final adminSeenProvider =
    NotifierProvider<AdminSeenNotifier, Map<String, int>>(
        AdminSeenNotifier.new);

/// Live `route → badge count` for the admin drawer.
///
/// Every count is derived from the same realtime streams the pages themselves
/// use, so a badge appears the moment a record is created and disappears the
/// moment it is actioned — no polling, no stale numbers (spec §22).
final adminBadgeCountsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final seen = ref.watch(adminSeenProvider);

  /// Counts records that still need action AND landed after the last visit.
  int countNew(Iterable<DateTime> createdAts, String route) {
    final since = seen[route] ?? 0;
    return createdAts
        .where((d) => d.millisecondsSinceEpoch > since)
        .length;
  }

  final pendingProfiles =
      ref.watch(pendingProfilesProvider).valueOrNull ?? const [];
  final appointments =
      ref.watch(allAppointmentsProvider).valueOrNull ?? const [];
  final reportRequests =
      ref.watch(allReportRequestsProvider).valueOrNull ?? const [];
  final userReports = ref.watch(allReportsProvider).valueOrNull ?? const [];
  final astrologers = ref.watch(allAstrologersProvider).valueOrNull ?? const [];

  return {
    // Profiles awaiting verification — the queue provider is already filtered
    // to pending, so every row here is action-required.
    AdminBadgeSection.pendingVerification: countNew(
        pendingProfiles.map((p) => p.createdAt),
        AdminBadgeSection.pendingVerification),
    // Bookings the admin has not yet confirmed or cancelled.
    AdminBadgeSection.appointments: countNew(
        appointments
            .where((a) => a.status == AstrologerRequestStatus.pending)
            .map((a) => a.createdAt),
        AdminBadgeSection.appointments),
    // Paid report requests still waiting to be picked up.
    AdminBadgeSection.horoscopeRequests: countNew(
        reportRequests
            .where((r) => r.status == AstrologerRequestStatus.pending)
            .map((r) => r.createdAt),
        AdminBadgeSection.horoscopeRequests),
    // Member reports that have not been reviewed.
    AdminBadgeSection.userReports: countNew(
        userReports
            .where((r) => !r.isResolved && r.status == 'pending')
            .map((r) => r.createdAt),
        AdminBadgeSection.userReports),
    // Employee accounts awaiting approval (createdAt is null on older docs —
    // those count as "always new" until the section is opened once).
    AdminBadgeSection.employees: countNew(
        astrologers
            .where((a) => a.status == VerificationStatus.pending)
            .map((a) => a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(1)),
        AdminBadgeSection.employees),
  };
});
