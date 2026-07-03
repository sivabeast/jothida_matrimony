import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/banner_model.dart';
import 'service_providers.dart';

/// PUBLISHED Home banners (enabled, by display order) — what users see.
final activeBannersProvider =
    StreamProvider.autoDispose<List<HomeBannerModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchActiveBanners();
});

/// ALL banners (any status) for the admin Banner Management screen.
final allBannersProvider =
    StreamProvider.autoDispose<List<HomeBannerModel>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllBanners();
});

/// Admin CRUD / ordering / publish controller for Home banners.
class BannerController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create(HomeBannerModel banner) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).createBanner(banner));
  }

  Future<void> update(String id, Map<String, dynamic> fields) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).updateBanner(id, fields));
  }

  Future<void> setEnabled(String id, bool enabled) =>
      update(id, {'enabled': enabled});

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(firestoreServiceProvider).deleteBanner(id));
  }

  /// Moves [banner] one position up (-1) or down (+1) within [all] (already
  /// sorted by order). No-op at the edges. Orders are swapped atomically; when
  /// two banners share the same stored order the swap uses their list indices
  /// so the move is still visible.
  Future<void> move(
      List<HomeBannerModel> all, HomeBannerModel banner, int delta) async {
    final i = all.indexWhere((b) => b.id == banner.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= all.length) return;
    final other = all[j];
    var orderA = banner.order;
    var orderB = other.order;
    if (orderA == orderB) {
      // Degenerate orders (e.g. legacy docs all 0) — derive from positions.
      orderA = i;
      orderB = j;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref
        .read(firestoreServiceProvider)
        .swapBannerOrder(banner.id, orderA, other.id, orderB));
  }
}

final bannerControllerProvider =
    NotifierProvider<BannerController, AsyncValue<void>>(BannerController.new);
