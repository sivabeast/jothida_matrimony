import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/l10n_ext.dart';
import '../../providers/auth_provider.dart';

/// ── Launch-version feature locks ────────────────────────────────────────────
///
/// Marriage Fixed, the Wedding (Marriage) Workspace, Family Member Login and
/// the Muhurtham Calendar are NOT part of the initial release. They stay in
/// the app but are shown LOCKED (🔒 + "Coming Soon") for every regular user.
/// Only admin accounts keep full access, so the features can still be used
/// and verified internally.
///
/// This file is the ONE shared lock implementation (same icon, badge, dialog
/// and page everywhere) — never hand-roll a per-screen variant.

/// True when the signed-in account may use the locked upcoming features —
/// i.e. an admin ('admin' / 'super_admin') account. Everyone else sees the
/// Coming Soon lock state.
final upcomingFeaturesUnlockedProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? false;
});

/// The shared "Coming Soon" pill badge shown beside a locked feature's title.
class ComingSoonBadge extends StatelessWidget {
  final bool compact;
  const ComingSoonBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldDark.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: compact ? 10 : 12, color: AppColors.goldDark),
          const SizedBox(width: 3),
          Text(
            context.l10n.comingSoon,
            style: TextStyle(
              color: AppColors.goldDark,
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared Coming Soon dialog shown when a locked feature is tapped.
Future<void> showComingSoonDialog(BuildContext context,
    {required String featureName}) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock, color: AppColors.goldDark, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(featureName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ComingSoonBadge(),
          const SizedBox(height: 12),
          Text(l10n.comingSoonBody,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.ok),
        ),
      ],
    ),
  );
}

/// The shared full-page Coming Soon state — shown instead of a locked page
/// (Wedding/Marriage Workspace, Muhurtham Calendar) for non-admin users.
class ComingSoonPage extends StatelessWidget {
  final String featureName;

  /// Extra action below "Go Back" (e.g. Sign Out for locked family accounts
  /// that have no other reachable screen).
  final Widget? extraAction;

  const ComingSoonPage({super.key, required this.featureName, this.extraAction});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(featureName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.goldDark.withOpacity(0.4)),
                ),
                child: const Icon(Icons.lock_outline,
                    size: 44, color: AppColors.goldDark),
              ),
              const SizedBox(height: 18),
              Text(featureName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins')),
              const SizedBox(height: 8),
              const ComingSoonBadge(),
              const SizedBox(height: 14),
              Text(l10n.comingSoonBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/home');
                  }
                },
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.goBack),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
              if (extraAction != null) ...[
                const SizedBox(height: 8),
                extraAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
