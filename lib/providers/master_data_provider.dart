import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/master_data.dart';
import '../services/firebase/master_data_service.dart';

final masterDataServiceProvider =
    Provider<MasterDataService>((ref) => MasterDataService());

/// All religions (master_religions), name-sorted.
final religionsProvider = FutureProvider.autoDispose<List<Religion>>((ref) {
  return ref.watch(masterDataServiceProvider).getReligions();
});

/// Castes for a given religionId (empty when none selected). Cached per
/// religionId so switching back and forth doesn't refetch.
final castesProvider =
    FutureProvider.autoDispose.family<List<Caste>, String>((ref, religionId) {
  if (religionId.isEmpty) return Future.value(const <Caste>[]);
  return ref.watch(masterDataServiceProvider).getCastes(religionId);
});

/// Subcastes for a given casteId (empty when none selected).
final subcastesProvider =
    FutureProvider.autoDispose.family<List<Subcaste>, String>((ref, casteId) {
  if (casteId.isEmpty) return Future.value(const <Subcaste>[]);
  return ref.watch(masterDataServiceProvider).getSubcastes(casteId);
});
