import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/announcement_model.dart';
import 'service_providers.dart';

/// Live, active announcements (newest first) — shown to every user & astrologer.
final announcementsProvider =
    StreamProvider.autoDispose<List<AnnouncementModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAnnouncements();
});

/// All announcements (any status) for the admin management screen.
final allAnnouncementsProvider =
    StreamProvider.autoDispose<List<AnnouncementModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllAnnouncements();
});

/// Admin CRUD controller for announcements.
class AnnouncementController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create({required String title, required String message}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(firestoreServiceProvider)
        .createAnnouncement(title: title, message: message));
  }

  Future<void> update(
    String id, {
    required String title,
    required String message,
    required bool isActive,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(firestoreServiceProvider)
        .updateAnnouncement(id,
            title: title, message: message, isActive: isActive));
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).deleteAnnouncement(id));
  }
}

final announcementControllerProvider =
    NotifierProvider<AnnouncementController, AsyncValue<void>>(
        AnnouncementController.new);

// ── Unread tracking (per-device) ─────────────────────────────────────────────
// Announcements are global, so "unread" is tracked locally: the timestamp the
// user last opened their notifications screen. Anything newer counts as unread.

const String _kLastSeenKey = 'announcements_last_seen_ms';

class AnnouncementsSeenNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getInt(_kLastSeenKey) ?? 0;
    } catch (_) {/* keep 0 */}
  }

  /// Marks all current announcements as seen (call when the inbox is opened).
  Future<void> markSeen() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    state = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastSeenKey, now);
    } catch (_) {/* best-effort */}
  }
}

final announcementsLastSeenProvider =
    NotifierProvider<AnnouncementsSeenNotifier, int>(
        AnnouncementsSeenNotifier.new);

/// Number of announcements created after the user last opened the inbox.
final unreadAnnouncementsCountProvider = Provider.autoDispose<int>((ref) {
  final lastSeen = ref.watch(announcementsLastSeenProvider);
  final list =
      ref.watch(announcementsProvider).valueOrNull ?? const <AnnouncementModel>[];
  return list
      .where((a) => a.createdAt.millisecondsSinceEpoch > lastSeen)
      .length;
});
