import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/porutham_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/porutham_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/common/gradient_button.dart';

class PoruthamsScreen extends ConsumerWidget {
  const PoruthamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myPoruthams = ref.watch(myPoruthamsProvider);
    final subAsync = ref.watch(activeSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Porutham Analysis'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What is Porutham?',
                      style: AppTextStyles.heading3.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text(
                    'Porutham (Compatibility Analysis) is performed by our certified astrologers based on 6 key criteria: Dina, Gana, Mahendra, Rajju, Yoni, and Rasi Porutham.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  subAsync.when(
                    data: (sub) => Text(
                      sub != null
                          ? 'Free requests remaining with your plan'
                          : 'Price: ₹${AppConstants.poruthamsRequestPrice} per analysis',
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.bold),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('My Porutham Requests', style: AppTextStyles.heading2),
            const SizedBox(height: 16),
            myPoruthams.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (list) => list.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _PoruthamsCard(model: list[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Icon(Icons.star_outline, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No porutham requests yet',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text(
              'Browse profiles and request porutham analysis to check compatibility.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
}

class _PoruthamsCard extends StatelessWidget {
  final PoruthamsModel model;

  const _PoruthamsCard({required this.model});

  @override
  Widget build(BuildContext context) {
    final result = model.result;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${model.brideName} & ${model.groomName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                _StatusChip(model.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Requested: ${_formatDate(model.requestedAt)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (result != null) ...[
              const Divider(height: 24),
              _MatchBar(matched: result.matchedCount),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PortuthamChip('Dina', result.dinaPorutham),
                  _PortuthamChip('Gana', result.ganaPorutham),
                  _PortuthamChip('Mahendra', result.mahendraPorutham),
                  _PortuthamChip('Rajju', result.rajjuPorutham),
                  _PortuthamChip('Yoni', result.yoniPorutham),
                  _PortuthamChip('Rasi', result.rasiPorutham),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Verdict: ${result.finalVerdict}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              if (result.astrologerNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Astrologer Notes:', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(result.astrologerNotes, style: const TextStyle(color: Colors.grey)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = status == 'completed' ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _MatchBar extends StatelessWidget {
  final int matched;
  const _MatchBar({required this.matched});

  @override
  Widget build(BuildContext context) {
    final pct = matched / 6;
    final color = pct >= 0.67
        ? Colors.green
        : pct >= 0.5
            ? Colors.orange
            : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Match Score', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('$matched/6 (${(pct * 100).round()}%)',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: pct,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

class _PortuthamChip extends StatelessWidget {
  final String label;
  final bool matched;
  const _PortuthamChip(this.label, this.matched);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: matched ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: matched ? Colors.green[200]! : Colors.red[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(matched ? Icons.check : Icons.close,
              size: 14, color: matched ? Colors.green : Colors.red),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: matched ? Colors.green : Colors.red)),
        ],
      ),
    );
  }
}
