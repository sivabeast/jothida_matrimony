import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/porutham_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/porutham_provider.dart';
import '../../providers/service_providers.dart';

class AdminPoruthamsScreen extends ConsumerWidget {
  const AdminPoruthamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingPoruthamsProvider);

    return pendingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) => list.isEmpty
          ? const Center(child: Text('No pending porutham requests'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _PoruthamsRequestCard(model: list[i]),
            ),
    );
  }
}

class _PoruthamsRequestCard extends ConsumerWidget {
  final PoruthamsModel model;

  const _PoruthamsRequestCard({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${model.brideName} & ${model.groomName}',
                style: AppTextStyles.heading3),
            const SizedBox(height: 4),
            Text(
              'Requested: ${model.requestedAt.day}/${model.requestedAt.month}/${model.requestedAt.year}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Text(
              model.isFreeRequest ? 'Free request' : 'Paid: ₹${model.amountPaid}',
              style: TextStyle(
                color: model.isFreeRequest ? Colors.green : AppColors.primary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showSubmitDialog(context, ref),
              icon: const Icon(Icons.edit, color: Colors.white),
              label: const Text('Submit Analysis', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubmitDialog(BuildContext context, WidgetRef ref) async {
    final Map<String, bool> poruthams = {
      'dinaPorutham': false,
      'ganaPorutham': false,
      'mahendraPorutham': false,
      'rajjuPorutham': false,
      'yoniPorutham': false,
      'rasiPorutham': false,
    };
    final notesController = TextEditingController();
    String verdict = 'Average Match';

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Submit Porutham Analysis'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...poruthams.keys.map((key) => CheckboxListTile(
                      title: Text(_formatKey(key)),
                      value: poruthams[key],
                      onChanged: (v) => setState(() => poruthams[key] = v ?? false),
                      activeColor: AppColors.primary,
                    )),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: verdict,
                  onChanged: (v) => setState(() => verdict = v!),
                  items: const [
                    DropdownMenuItem(value: 'Suitable Match', child: Text('Suitable Match')),
                    DropdownMenuItem(value: 'Average Match', child: Text('Average Match')),
                    DropdownMenuItem(value: 'Not Recommended', child: Text('Not Recommended')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Final Verdict',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Astrologer Notes',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final userId = ref.read(firebaseAuthStreamProvider).valueOrNull?.uid ?? '';
                final userModel = await ref.read(authRepositoryProvider).getUserModel(userId);
                final result = PoruthamsResult(
                  dinaPorutham: poruthams['dinaPorutham']!,
                  ganaPorutham: poruthams['ganaPorutham']!,
                  mahendraPorutham: poruthams['mahendraPorutham']!,
                  rajjuPorutham: poruthams['rajjuPorutham']!,
                  yoniPorutham: poruthams['yoniPorutham']!,
                  rasiPorutham: poruthams['rasiPorutham']!,
                  finalVerdict: verdict,
                  astrologerNotes: notesController.text,
                  astrologerName: userModel?.displayName ?? 'Astrologer',
                  analyzedAt: DateTime.now(),
                );
                await ref.read(poruthamsNotifierProvider.notifier)
                    .submitResult(model.id, result, userId);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    notesController.dispose();
  }

  String _formatKey(String key) {
    switch (key) {
      case 'dinaPorutham':
        return 'Dina Porutham';
      case 'ganaPorutham':
        return 'Gana Porutham';
      case 'mahendraPorutham':
        return 'Mahendra Porutham';
      case 'rajjuPorutham':
        return 'Rajju Porutham';
      case 'yoniPorutham':
        return 'Yoni Porutham';
      case 'rasiPorutham':
        return 'Rasi Porutham';
      default:
        return key;
    }
  }
}
