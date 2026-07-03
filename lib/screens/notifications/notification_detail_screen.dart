import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// Everything the details page needs, independent of whether the source was a
/// per-user `notifications` document or an admin `announcements` broadcast.
class NotificationDetailArgs {
  final String title;
  final String body;
  final DateTime date;

  /// Human-readable type label shown as a chip ("Offer", "Interest"…).
  final String typeLabel;
  final IconData icon;
  final Color color;

  /// Optional related action: an external URL (https://…) or an internal app
  /// route (starting with '/'). Empty/null = no action button.
  final String? actionUrl;

  /// Label for the action button ("Update Now", "Open", "Learn More"…).
  final String actionLabel;

  const NotificationDetailArgs({
    required this.title,
    required this.body,
    required this.date,
    required this.typeLabel,
    required this.icon,
    required this.color,
    this.actionUrl,
    this.actionLabel = 'Open',
  });

  bool get hasAction => (actionUrl ?? '').trim().isNotEmpty;
}

/// Full-page details of a single notification: complete title + description,
/// exact date & time, its type, and the related action button (if any). The
/// caller marks the notification read BEFORE opening this page.
class NotificationDetailScreen extends StatelessWidget {
  final NotificationDetailArgs args;
  const NotificationDetailScreen({super.key, required this.args});

  Future<void> _openAction(BuildContext context) async {
    final raw = (args.actionUrl ?? '').trim();
    if (raw.isEmpty) return;

    // Internal app page → in-app navigation.
    if (raw.startsWith('/')) {
      context.push(raw);
      return;
    }

    // External link (website, Play Store…) → open outside the app.
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(
        raw.startsWith('http://') || raw.startsWith('https://')
            ? raw
            : 'https://$raw');
    if (uri == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('This link could not be opened.')));
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(
            const SnackBar(content: Text('This link could not be opened.')));
      }
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('This link could not be opened.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('d MMMM yyyy · h:mm a').format(args.date);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Notification'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: args.color.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(args.icon, color: args.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: args.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(args.typeLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: args.color)),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(Icons.schedule,
                                  size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(dateText,
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600])),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Text(
                  args.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (args.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    args.body,
                    style: TextStyle(
                        fontSize: 14, height: 1.55, color: Colors.grey[800]),
                  ),
                ],
                if (args.hasAction) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openAction(context),
                      icon: Icon(
                          args.actionUrl!.trim().startsWith('/')
                              ? Icons.arrow_forward
                              : Icons.open_in_new,
                          size: 18),
                      label: Text(args.actionLabel,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
