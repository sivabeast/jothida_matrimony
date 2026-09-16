import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import '../services/cloudinary/cloudinary_storage_service.dart';
import '../widgets/common/network_photo.dart' show evictCachedImage;
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Create / read / delete / replace for the signed-in user's horoscope
/// documents — MULTIPLE images and MULTIPLE PDFs.
///
/// Files live on Cloudinary. A delete or a replace does TWO things, in this
/// order: the reference comes off the profile document first, and only then is
/// the remote asset destroyed (spec §10/§24). Unlinking first is what makes the
/// operation safe — if the destroy fails the member has simply lost a file they
/// asked to remove, never a file they still expect to see.
///
/// The destroy itself must be signed with the Cloudinary API secret, which
/// never ships in the app, so it runs in the `deleteCloudinaryAssets` Cloud
/// Function; anything it cannot delete is queued in `cloudinary_cleanup` rather
/// than left as an invisible orphan (spec §32).
class HoroscopeFilesController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  ProfileModel? get _profile => ref.read(myProfileProvider).valueOrNull;

  Future<void> _persist(HoroscopeDetails horoscope) async {
    final p = _profile;
    if (p == null) throw StateError('No profile to update');
    final updated = p.copyWith(horoscope: horoscope);
    if (kBypassAuth) {
      ref.read(demoProfilesProvider.notifier).upsert(updated);
    } else {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(p.id, {'horoscope': horoscope.toMap()});
      ref.invalidate(myProfileProvider);
    }
  }

  Future<void> _run(Future<void> Function() body) async {
    state = const AsyncLoading();
    try {
      await body();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<String> _upload(File file, {required bool isPdf}) {
    final p = _profile!;
    return ref
        .read(profileRepositoryProvider)
        .uploadHoroscopeDoc(userId: p.userId, file: file, isPdf: isPdf);
  }

  /// Destroys the Cloudinary asset behind [url] once it is no longer referenced
  /// by the profile. Never throws — an unlink that succeeded must not be
  /// reported as a failure because the remote cleanup did not.
  Future<void> _destroy(String url, String reason) async {
    if (url.trim().isEmpty || kBypassAuth) return;
    await evictCachedImage(url);
    try {
      final storage = ref.read(storageServiceProvider);
      if (storage is! CloudinaryStorageService) return;
      final deleted = await storage.deleteFiles([url], reason: reason);
      debugPrint('[HoroscopeFiles] destroyed $deleted asset(s) ($reason).');
    } catch (e) {
      debugPrint('[HoroscopeFiles] asset cleanup skipped: $e');
    }
  }

  // ── Images ────────────────────────────────────────────────────────────────
  Future<void> addImages(List<File> files) => _run(() async {
        final p = _profile;
        if (p == null || files.isEmpty) return;
        final urls = [...p.horoscope.horoscopeImages];
        for (final f in files) {
          urls.add(await _upload(f, isPdf: false));
        }
        await _persist(p.horoscope.copyWith(horoscopeImages: urls));
      });

  Future<void> deleteImage(String url) => _run(() async {
        final p = _profile;
        if (p == null) return;
        final urls =
            p.horoscope.horoscopeImages.where((u) => u != url).toList();
        await _persist(p.horoscope.copyWith(horoscopeImages: urls));
        await _destroy(url, 'horoscope_image_deleted:${p.userId}');
      });

  Future<void> replaceImage(String oldUrl, File newFile) => _run(() async {
        final p = _profile;
        if (p == null) return;
        final newUrl = await _upload(newFile, isPdf: false);
        final urls = p.horoscope.horoscopeImages
            .map((u) => u == oldUrl ? newUrl : u)
            .toList();
        if (!urls.contains(newUrl)) urls.add(newUrl);
        await _persist(p.horoscope.copyWith(horoscopeImages: urls));
        // Only once the replacement is safely stored (spec §6/§24).
        if (!urls.contains(oldUrl)) {
          await _destroy(oldUrl, 'horoscope_image_replaced:${p.userId}');
        }
      });

  // ── PDFs (folds the legacy single PDF into the multi-PDF list) ───────────────
  Future<void> addPdfs(List<File> files) => _run(() async {
        final p = _profile;
        if (p == null || files.isEmpty) return;
        final urls = [...p.horoscope.allPdfUrls];
        for (final f in files) {
          urls.add(await _upload(f, isPdf: true));
        }
        await _persist(p.horoscope
            .copyWith(horoscopePdfUrls: urls, horoscopePdfUrl: ''));
      });

  Future<void> deletePdf(String url) => _run(() async {
        final p = _profile;
        if (p == null) return;
        final urls = p.horoscope.allPdfUrls.where((u) => u != url).toList();
        await _persist(p.horoscope
            .copyWith(horoscopePdfUrls: urls, horoscopePdfUrl: ''));
        await _destroy(url, 'horoscope_pdf_deleted:${p.userId}');
      });

  Future<void> replacePdf(String oldUrl, File newFile) => _run(() async {
        final p = _profile;
        if (p == null) return;
        final newUrl = await _upload(newFile, isPdf: true);
        final urls = p.horoscope.allPdfUrls
            .map((u) => u == oldUrl ? newUrl : u)
            .toList();
        if (!urls.contains(newUrl)) urls.add(newUrl);
        await _persist(p.horoscope
            .copyWith(horoscopePdfUrls: urls, horoscopePdfUrl: ''));
        if (!urls.contains(oldUrl)) {
          await _destroy(oldUrl, 'horoscope_pdf_replaced:${p.userId}');
        }
      });
}

final horoscopeFilesControllerProvider =
    NotifierProvider<HoroscopeFilesController, AsyncValue<void>>(
        HoroscopeFilesController.new);
