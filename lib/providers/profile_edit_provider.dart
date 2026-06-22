import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/dev_config.dart';
import '../models/profile_model.dart';
import 'demo_data_provider.dart';
import 'profile_provider.dart';
import 'service_providers.dart';

/// Persists a single profile-section edit.
///
/// [updated] is the full edited model (used for the in-memory demo store);
/// [patch] is the Firestore field subset for just that section (used in real
/// mode). After saving, `myProfileProvider` is re-read so the completion
/// percentage and the Home card update immediately.
class ProfileEditController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> save({
    required ProfileModel updated,
    required Map<String, dynamic> patch,
  }) async {
    state = const AsyncLoading();
    try {
      final current = ref.read(myProfileProvider).valueOrNull;
      if (current == null) throw StateError('No profile to update');
      if (kBypassAuth) {
        ref.read(demoProfilesProvider.notifier).upsert(updated);
      } else {
        await ref
            .read(profileRepositoryProvider)
            .updateProfile(current.id, patch);
        ref.invalidate(myProfileProvider);
      }
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final profileEditControllerProvider =
    NotifierProvider<ProfileEditController, AsyncValue<void>>(
        ProfileEditController.new);
