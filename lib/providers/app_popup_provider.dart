import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_popup_model.dart';
import 'auth_provider.dart';
import 'service_providers.dart';

/// ACTIVE popups in display order — the rotation users see (spec §14).
final activePopupsProvider =
    StreamProvider.autoDispose<List<AppPopupModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchActivePopups();
});

/// ALL popups (any status) for the admin management screen.
final allPopupsProvider = StreamProvider.autoDispose<List<AppPopupModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllPopups();
});

/// Where this user has reached in the popup rotation.
///
/// Stored per account on the device: opening the app shows the NEXT active
/// popup, and the cursor advances so the following launch shows the one after
/// it, wrapping around at the end (spec §14).
///
/// The cursor is an ever-increasing counter rather than an index, so the
/// rotation stays sane when the admin adds, removes or reorders contents — it
/// is taken modulo the current list length at read time.
class PopupRotationStore {
  static const _prefix = 'app_popup_cursor_';

  final String uid;
  const PopupRotationStore(this.uid);

  String get _key => '$_prefix$uid';

  Future<int> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  Future<void> advance() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_key) ?? 0) + 1;
    // Keep the stored number small; only its remainder is ever used.
    await prefs.setInt(_key, next % 100000);
  }
}

/// True once this app session has already shown its popup.
///
/// A popup appears ONCE per app opening: closing it must not let it (or the
/// next one) pop up again while the app stays open. This is deliberately
/// in-memory — a fresh launch starts a fresh session and shows the next
/// content (spec §14).
final popupShownThisSessionProvider = StateProvider<bool>((ref) => false);

/// The popup to show for this app opening, or null when there is nothing to
/// show — no active contents, or one has already been shown this session.
///
/// Resolving this does NOT advance the rotation; the caller advances it when
/// the popup is actually displayed, so a popup that never got shown (because
/// the list was still loading) is not silently skipped.
final nextPopupProvider = FutureProvider.autoDispose<AppPopupModel?>((ref) async {
  if (ref.watch(popupShownThisSessionProvider)) return null;
  final popups = await ref.watch(activePopupsProvider.future);
  if (popups.isEmpty) return null;
  final uid = ref.watch(firebaseAuthStreamProvider).valueOrNull?.uid ?? 'guest';
  final cursor = await PopupRotationStore(uid).read();
  return popups[cursor % popups.length];
});

/// Admin CRUD / ordering / publish controller for app-opening popups.
class PopupController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create(AppPopupModel popup) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).createPopup(popup));
  }

  Future<void> update(String id, Map<String, dynamic> fields) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).updatePopup(id, fields));
  }

  Future<void> setEnabled(String id, bool enabled) =>
      update(id, {'enabled': enabled});

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).deletePopup(id));
  }

  /// Moves [popup] one position up (-1) or down (+1) within [all] (already
  /// sorted by order). No-op at the edges. Degenerate orders (legacy documents
  /// all sharing 0) fall back to list positions so the move is still visible.
  Future<void> move(
      List<AppPopupModel> all, AppPopupModel popup, int delta) async {
    final i = all.indexWhere((p) => p.id == popup.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= all.length) return;
    final other = all[j];
    var orderA = popup.order;
    var orderB = other.order;
    if (orderA == orderB) {
      orderA = i;
      orderB = j;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(firestoreServiceProvider)
        .swapPopupOrder(popup.id, orderA, other.id, orderB));
  }
}

final popupControllerProvider =
    NotifierProvider<PopupController, AsyncValue<void>>(PopupController.new);
