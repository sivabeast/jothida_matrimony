import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/file_actions.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/astrologer_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/match_analysis_provider.dart';

/// "My Match Analysis" — the user's view of the porutham requests they booked
/// with astrologers, in Pending / Accepted / Completed tabs. Completed requests
/// expose the astrologer's report (text + images + PDFs); accepted & completed
/// requests unlock a chat with that astrologer.
class MyMatchAnalysisScreen extends ConsumerWidget {
  const MyMatchAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myMatchAnalysisRequestsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          title: const Text('My Match Analysis'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Accepted'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => _error(ref),
          data: (all) {
            // Pending tab also surfaces rejected outcomes (status chip makes the
            // result clear) so nothing the user booked silently disappears.
            final pending = all
                .where((r) =>
                    r.status == AstrologerRequestStatus.pending ||
                    r.status == AstrologerRequestStatus.rejected)
                .toList();
            final accepted = all
                .where((r) => r.status == AstrologerRequestStatus.accepted)
                .toList();
            final completed = all
                .where((r) => r.status == AstrologerRequestStatus.completed)
                .toList();
            return TabBarView(
              children: [
                _list(pending, 'No pending requests'),
                _list(accepted, 'No accepted requests yet'),
                _list(completed, 'No completed analysis yet'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(List<AstrologerRequestModel> items, String emptyMsg) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 56, color: AppColors.primary.withOpacity(0.35)),
              const SizedBox(height: 12),
              Text(emptyMsg,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AnalysisCard(request: items[i]),
    );
  }

  Widget _error(WidgetRef ref) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Could not load your analysis'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(myMatchAnalysisRequestsProvider),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
}

class _AnalysisCard extends ConsumerWidget {
  final AstrologerRequestModel request;
  const _AnalysisCard({required this.request});

  Color _statusColor(AstrologerRequestStatus s) {
    switch (s) {
      case AstrologerRequestStatus.pending:
        return AppColors.warning;
      case AstrologerRequestStatus.accepted:
        return AppColors.info;
      case AstrologerRequestStatus.completed:
        return AppColors.success;
      case AstrologerRequestStatus.rejected:
        return AppColors.error;
    }
  }

  Future<void> _chat(BuildContext context, WidgetRef ref) async {
    try {
      final photo =
          ref.read(astrologerByIdProvider(request.astrologerId))?.photoUrl ?? '';
      final id = await ref.read(chatControllerProvider).openChatWith(
            otherUid: request.astrologerId,
            otherName: request.astrologerName.isEmpty
                ? 'Astrologer'
                : request.astrologerName,
            otherPhoto: photo,
          );
      if (!context.mounted) return;
      context.push('/chat/$id', extra: {
        'name':
            request.astrologerName.isEmpty ? 'Astrologer' : request.astrologerName,
        'photo': photo,
      });
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open chat. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final color = _statusColor(r.status);
    final canChat = r.status == AstrologerRequestStatus.accepted ||
        r.status == AstrologerRequestStatus.completed;
    final canViewReport =
        r.status == AstrologerRequestStatus.completed && r.hasAnalysis;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.astrologerName.isEmpty
                      ? 'Astrologer'
                      : r.astrologerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.status.label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.favorite, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${r.profileAName ?? 'Groom'}  ×  ${r.profileBName ?? 'Bride'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(DateFormat('d MMM yyyy, h:mm a').format(r.createdAt),
              style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
          if (r.message.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          ],
          if (canChat || canViewReport) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (canViewReport)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showReport(context, r),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('View Report'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                if (canViewReport && canChat) const SizedBox(width: 10),
                if (canChat)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _chat(context, ref),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('Chat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showReport(BuildContext context, AstrologerRequestModel r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Analysis by ${r.astrologerName.isEmpty ? 'Astrologer' : r.astrologerName}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${r.profileAName ?? 'Groom'}  ×  ${r.profileBName ?? 'Bride'}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const Divider(height: 26),
              if (r.analysisText.trim().isNotEmpty) ...[
                const Text('Report',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text(r.analysisText,
                    style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 18),
              ],
              if (r.analysisImages.isNotEmpty) ...[
                const Text('Images',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: r.analysisImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => showImageGallery(context, r.analysisImages,
                          initialIndex: i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          r.analysisImages[i],
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 110,
                            height: 110,
                            color: AppColors.primary.withOpacity(0.08),
                            child: const Icon(Icons.broken_image_outlined,
                                color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (r.analysisPdfs.isNotEmpty) ...[
                const Text('PDFs',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                for (var i = 0; i < r.analysisPdfs.length; i++)
                  RemotePdfTile(
                      url: r.analysisPdfs[i],
                      label: 'Analysis PDF ${i + 1}',
                      index: i),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
