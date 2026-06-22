import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Create / read / delete / replace for the signed-in user's horoscope
/// documents — MULTIPLE images and MULTIPLE PDFs.
///
/// Files are stored on Cloudinary (unsigned uploads can't be deleted from the
/// client), so "delete" removes the URL reference from the profile document;
/// the orphaned remote asset is simply no longer linked.
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
      });
}

final horoscopeFilesControllerProvider =
    NotifierProvider<HoroscopeFilesController, AsyncValue<void>>(
        HoroscopeFilesController.new);
