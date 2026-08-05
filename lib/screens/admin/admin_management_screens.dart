import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_plan.dart';

/// Admin management section screens, registered under the admin ShellRoute:
///   /admin/settings (AdminSettingsScreen — the Settings hub) and
///   /admin/revenue-settings (RevenueSettingsScreen — read-only pricing).
///
/// The old unrouted AstrologerManagementScreen and AnalyticsScreen were
/// removed: employees live at /admin/astrologers and charts/analytics at
/// /admin/analytics (AdminReportsPage).

// ─────────────────────────────────────────────────────────────────────────────
// Shared building blocks
// ─────────────────────────────────────────────────────────────────────────────

Widget _adminScaffold({
  required String title,
  required IconData icon,
  required String subtitle,
  required List<Widget> children,
}) {
  return Scaffold(
    backgroundColor: AppColors.scaffoldBg,
    appBar: AppBar(
      title: Text(title),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminHeader(icon: icon, title: title, subtitle: subtitle),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _AdminHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _AdminHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.withValues(alpha: 0.12),
          child: Icon(icon, color: c),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

/// Poppins section heading used between tile groups.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                color: AppColors.textPrimary)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ⚙️ Admin Settings
// ─────────────────────────────────────────────────────────────────────────────

/// Settings hub — every platform control lives here, so the other tabs stay
/// focused. Real management screens are linked directly.
class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] AdminSettings build — /admin/settings');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _AdminHeader(
          icon: Icons.settings,
          title: 'Settings',
          subtitle: 'Platform controls & configuration',
        ),
        const SizedBox(height: 16),
        // ── Member provisioning ─────────────────────────────────────────────
        // For members who cannot use the app themselves: the admin creates the
        // full matrimony profile through the SAME wizard members use, then
        // hands over the login (with a one-tap WhatsApp share).
        _ActionTile(
          icon: Icons.person_add_alt_1,
          title: 'Create Matrimony Profile',
          subtitle:
              'Create a profile on a member\'s behalf and give them a login',
          color: AppColors.primary,
          onTap: () => context.go('/admin/create-profile'),
        ),
        _ActionTile(
          icon: Icons.fact_check_outlined,
          title: 'Profile Approvals',
          subtitle: 'Review pending profiles — approve or reject',
          color: AppColors.warning,
          onTap: () => context.go('/admin/approvals'),
        ),
        _ActionTile(
          icon: Icons.history,
          title: 'Activity Log',
          subtitle: 'Audit trail of admin actions',
          onTap: () => context.go('/admin/activity-log'),
        ),
        const SizedBox(height: 4),
        // ── Core settings groups ────────────────────────────────────────────
        _ActionTile(
          icon: Icons.savings_outlined,
          title: 'Employee Commission',
          subtitle: 'Set the commission paid per completed report',
          color: AppColors.gold,
          onTap: () => context.go('/admin/commission'),
        ),
        // App updates need NO admin action at all (spec §9): Google Play
        // In-App Updates checks on every app open and shows the immediate
        // update dialog by itself. There is deliberately no settings page.
        _ActionTile(
          icon: Icons.notifications_outlined,
          title: 'Notification Management',
          subtitle: 'User & Employee notifications — send to all or selected',
          onTap: () => context.go('/admin/notifications'),
        ),
        _ActionTile(
          icon: Icons.auto_awesome_outlined,
          title: 'Astrology Management',
          subtitle:
              'Consultation service — working days, sessions & appointment rules',
          color: AppColors.primary,
          onTap: () => context.go('/admin/astrology-service'),
        ),
        _ActionTile(
          icon: Icons.event_note_outlined,
          title: 'Appointment Management',
          subtitle: 'View & manage all astrology appointment bookings',
          color: AppColors.primary,
          onTap: () => context.go('/admin/appointments'),
        ),
        const Divider(height: 28),
        const _SectionLabel('More'),
        // ── Other management areas (preserved) ──────────────────────────────
        _ActionTile(
          icon: Icons.flag_outlined,
          title: 'Reports',
          subtitle: 'Profile & chat reports — review, warn, suspend, delete',
          color: AppColors.error,
          onTap: () => context.go('/admin/reports'),
        ),
        _ActionTile(
          icon: Icons.view_carousel,
          title: 'Banner Management',
          subtitle: 'Home screen banners',
          onTap: () => context.go('/admin/banners'),
        ),
        _ActionTile(
          icon: Icons.science_outlined,
          title: 'Test Data',
          subtitle: 'Seed / delete dummy testing profiles',
          onTap: () => context.go('/admin/test-data'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 💰 Revenue Settings — read-only summary of current plan pricing
// ─────────────────────────────────────────────────────────────────────────────

class RevenueSettingsScreen extends StatelessWidget {
  const RevenueSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[Admin] RevenueSettings build — /admin/revenue-settings');
    return _adminScaffold(
      title: 'Revenue Settings',
      icon: Icons.payments_outlined,
      subtitle: 'Current service pricing (read-only)',
      children: [
        const _SectionLabel('Paid Astrology Services'),
        // The ONLY paid features — every matrimony feature is free.
        const _PriceRow('Horoscope Compatibility Report',
            AppConstants.horoscopeAnalysisFee, 'per report'),
        const _PriceRow('Astrologer Appointment',
            AppConstants.appointmentBookingFee, 'per booking'),
        const SizedBox(height: 12),
        const _SectionLabel('Astrologer Plans'),
        for (final p in AstrologerPlan.all)
          _PriceRow('${p.emoji} ${p.name}', p.currentPrice, p.periodLabel),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Free plans are not counted in revenue. Prices are defined in code (AppConstants / AstrologerPlan).',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final int price;
  final String period;
  const _PriceRow(this.label, this.price, this.period);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            Text('₹$price',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.success)),
            const SizedBox(width: 6),
            Text('/ $period',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ],
        ),
      );
}
