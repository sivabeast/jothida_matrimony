import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/dummy_profiles.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/service_providers.dart';

/// Admin **Test Data** tool (spec §3).
///
/// Seeds 10 male + 10 female realistic profiles into the `profiles` collection
/// (each tagged `isDummy: true`) so the app can be tested end-to-end, and lets
/// the admin bulk-delete them afterwards. Dummy docs can also be spotted in the
/// Firebase console by filtering `isDummy == true`.
class AdminTestDataScreen extends ConsumerStatefulWidget {
  const AdminTestDataScreen({super.key});

  @override
  ConsumerState<AdminTestDataScreen> createState() =>
      _AdminTestDataScreenState();
}

class _AdminTestDataScreenState extends ConsumerState<AdminTestDataScreen> {
  bool _busy = false;
  int? _count; // current dummy-profile count (null = still loading)

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    try {
      final c = await ref.read(firestoreServiceProvider).countDummyProfiles();
      if (mounted) setState(() => _count = c);
    } catch (_) {
      if (mounted) setState(() => _count = null);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _seed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final n = await ref
          .read(firestoreServiceProvider)
          .seedDummyProfiles(dummyProfiles());
      _snack('Seeded $n dummy profiles.');
      await _refreshCount();
    } catch (e) {
      _snack('Could not seed dummy profiles: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all dummy profiles?'),
        content: const Text(
            'This permanently removes every profile tagged as dummy '
            '(isDummy = true). Real user profiles are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await ref.read(firestoreServiceProvider).deleteDummyProfiles();
      _snack('Deleted $n dummy profiles.');
      await _refreshCount();
    } catch (e) {
      _snack('Could not delete dummy profiles: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Test Data'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.science_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Seed realistic dummy profiles (10 male + 10 female) for '
                    'testing. Every dummy is tagged isDummy = true, so you can '
                    'delete them all here — or filter them in the Firebase '
                    'console.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.groups_2_outlined,
                      color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  const Text('Current dummy profiles',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (count == null)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Text('$count',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _busy ? null : _seed,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_circle_outline),
            label: const Text('Seed 20 dummy profiles'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _deleteAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Delete all dummy profiles'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Re-seeding overwrites the same records (stable ids dummy_m1…/'
            'dummy_f1…) — it never creates duplicates.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
