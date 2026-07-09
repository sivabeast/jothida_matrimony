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

  Future<void> create({
    required String title,
    required String message,
    String type = 'general',
    String actionUrl = '',
    String actionLabel = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(firestoreServiceProvider).createAnnouncement(
            title: title,
            message: message,
            type: type,
            actionUrl: actionUrl,
            actionLabel: actionLabel));
  }

  Future<void> update(
    String id, {
    required String title,
    required String message,
    required bool isActive,
    String type = 'general',
    String actionUrl = '',
    String actionLabel = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(firestoreServiceProvider).updateAnnouncement(id,
            title: title,
            message: message,
            isActive: isActive,
            type: type,
            actionUrl: actionUrl,
            actionLabel: actionLabel));
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

// ── Read/unread tracking (per-device, per-announcement) ─────────────────────
// Announcements are global documents, so read state is tracked locally as a
// SET of announcement ids the user has OPENED. This fixes the old behaviour
// where merely opening the notifications LIST stamped a "last seen" time and
// silently marked everything read: now an announcement stays Unread until its
// details are actually opened, and once read it never shows as Unread again.
// The legacy last-seen timestamp is kept as a baseline so announcements from
// before this change don't all flip back to Unread.

const String _kLastSeenKey = 'announcements_last_seen_ms';
const String _kReadIdsKey = 'announcements_read_ids';

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
}

final announcementsLastSeenProvider =
    NotifierProvider<AnnouncementsSeenNotifier, int>(
        AnnouncementsSeenNotifier.new);

/// The ids of the announcements this device has opened (read).
class AnnouncementsReadNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getStringList(_kReadIdsKey) ?? const []).toSet();
    } catch (_) {/* keep empty */}
  }

  /// Marks one announcement as read (called when its details are opened).
  /// Permanent: a read announcement never becomes unread again.
  Future<void> markRead(String id) async {
    if (id.isEmpty || state.contains(id)) return;
    state = {...state, id};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kReadIdsKey, state.toList());
    } catch (_) {/* best-effort */}
  }

  /// Marks every listed announcement read at once — opening the Notifications
  /// page clears the whole badge (per the notification-flow spec).
  Future<void> markAllRead(Iterable<String> ids) async {
    final unread = ids.where((id) => id.isNotEmpty && !state.contains(id));
    if (unread.isEmpty) return;
    state = {...state, ...unread};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kReadIdsKey, state.toList());
    } catch (_) {/* best-effort */}
  }
}

final announcementsReadProvider =
    NotifierProvider<AnnouncementsReadNotifier, Set<String>>(
        AnnouncementsReadNotifier.new);

/// True when [a] has not been opened yet on this device (and is newer than the
/// legacy last-seen baseline).
bool isAnnouncementUnread(
    AnnouncementModel a, Set<String> readIds, int legacyLastSeenMs) {
  if (readIds.contains(a.id)) return false;
  return a.createdAt.millisecondsSinceEpoch > legacyLastSeenMs;
}

/// Number of unopened announcements — drives the bell badges.
final unreadAnnouncementsCountProvider = Provider.autoDispose<int>((ref) {
  final lastSeen = ref.watch(announcementsLastSeenProvider);
  final readIds = ref.watch(announcementsReadProvider);
  final list =
      ref.watch(announcementsProvider).valueOrNull ?? const <AnnouncementModel>[];
  return list.where((a) => isAnnouncementUnread(a, readIds, lastSeen)).length;
});
