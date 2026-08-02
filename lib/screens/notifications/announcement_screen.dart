import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../models/announcement_model.dart';
import '../../providers/announcement_provider.dart';
import '../../providers/navigation_provider.dart';

/// The Announcement screen — the DIRECT destination of every announcement
/// notification tap (`/announcement/:id`). Renders the full broadcast (image,
/// type, title, exact date, message, optional action) and marks it read.
/// There is deliberately no generic "notification details" page any more.
class AnnouncementScreen extends ConsumerStatefulWidget {
  final String announcementId;
  const AnnouncementScreen({super.key, required this.announcementId});

  @override
  ConsumerState<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends ConsumerState<AnnouncementScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the announcement is what marks it read (per-device tracking).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(announcementsReadProvider.notifier)
            .markRead(widget.announcementId);
      }
    });
  }

  static (IconData, Color) _visual(AnnouncementType t) => switch (t) {
        AnnouncementType.featureUpdate =>
          (Icons.new_releases_outlined, Colors.blue),
        AnnouncementType.offer => (Icons.local_offer_outlined, Colors.orange),
        AnnouncementType.maintenance =>
          (Icons.build_circle_outlined, Colors.brown),
        AnnouncementType.announcement => (Icons.campaign, AppColors.gold),
        _ => (Icons.notifications_none, AppColors.primary),
      };

  Future<void> _openAction(AnnouncementModel a) async {
    final raw = a.actionUrl.trim();
    if (raw.isEmpty) return;
    if (raw.startsWith('/')) {
      if (isReportsRoute(raw)) {
        goToReportsTab(context, ref);
      } else {
        context.push(raw);
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.linkCouldNotBeOpened;
    final uri = Uri.tryParse(
        raw.startsWith('http://') || raw.startsWith('https://')
            ? raw
            : 'https://$raw');
    if (uri == null) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(announcementByIdProvider(widget.announcementId));
    final a = async.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(context.l10n.notificationTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.isLoading && a == null
          ? const Center(child: CircularProgressIndicator())
          : a == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.l10n.noNotifications,
                        style: const TextStyle(color: Colors.grey)),
                  ),
                )
              : _body(a),
    );
  }

  Widget _body(AnnouncementModel a) {
    final (icon, color) = _visual(a.typeEnum);
    final dateText = DateFormat('d MMMM yyyy · h:mm a').format(a.createdAt);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (a.imageUrl.trim().isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: a.imageUrl.trim(),
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 180,
                color: color.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(a.typeEnum.label,
                        style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(a.title,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 19,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(dateText,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
              const Divider(height: 28),
              Text(a.message,
                  style: const TextStyle(fontSize: 14.5, height: 1.55)),
              if (a.hasAction) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openAction(a),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(a.effectiveActionLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
