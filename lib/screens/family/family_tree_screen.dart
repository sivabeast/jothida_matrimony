import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../providers/profile_provider.dart';

/// 🌳 Family Tree.
///
/// Renders a profile's [FamilyDetails] as an attractive, mobile-responsive tree
/// of cards + connectors:
///
///                 Family
///                   │
///         ┌─────────┴─────────┐
///       Father              Mother
///         │
///     Brothers / Sisters
///
///   Family Type · Family Status
///
/// Opened two ways:
///   • own family   → `/family-tree`            (loads [myProfileProvider])
///   • a match's    → `/family-tree-user/:uid`  (loads [profileByUserIdProvider])
///
/// The matched-user route is only reachable from a profile whose interest has
/// been accepted — the calling screen gates the entry button.
class FamilyTreeScreen extends ConsumerWidget {
  /// When set, shows the family tree of the OTHER user with this UID (an
  /// accepted match). When null, shows the signed-in user's own family tree.
  final String? userId;

  const FamilyTreeScreen({super.key, this.userId});

  bool get _isOther => userId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = _isOther
        ? ref.watch(profileByUserIdProvider(userId!))
        : ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Family Tree'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _Empty(
          icon: Icons.error_outline,
          title: 'Could not load family details',
          subtitle: 'Please try again in a moment.',
        ),
        data: (profile) {
          if (profile == null) {
            return _Empty(
              icon: Icons.person_off_outlined,
              title: _isOther ? 'Profile unavailable' : 'No profile yet',
              subtitle: _isOther
                  ? 'This member\'s details could not be loaded.'
                  : 'Create your profile to add family details.',
              actionLabel: _isOther ? null : 'Create Profile',
              onAction: _isOther ? null : () => context.push('/profile/create'),
            );
          }
          final family = profile.family;
          if (_isFamilyEmpty(family)) {
            return _Empty(
              icon: Icons.family_restroom_outlined,
              title: 'Family details not added',
              subtitle: _isOther
                  ? '${profile.name} hasn\'t shared family details yet.'
                  : 'Add your family details from Personal Details to see your '
                      'family tree here.',
              actionLabel: _isOther ? null : 'Add Family Details',
              onAction:
                  _isOther ? null : () => context.push('/personal-details'),
            );
          }
          return FamilyTreeView(family: family, personName: profile.name);
        },
      ),
    );
  }

  static bool _isFamilyEmpty(FamilyDetails f) =>
      f.fatherName.trim().isEmpty &&
      f.motherName.trim().isEmpty &&
      f.fatherOccupation.trim().isEmpty &&
      f.motherOccupation.trim().isEmpty &&
      f.brothersCount == 0 &&
      f.sistersCount == 0 &&
      f.familyType.trim().isEmpty &&
      f.familyStatus.trim().isEmpty;
}

/// The pure visual tree — reusable wherever a [FamilyDetails] needs rendering.
class FamilyTreeView extends StatelessWidget {
  final FamilyDetails family;
  final String personName;

  const FamilyTreeView({
    super.key,
    required this.family,
    this.personName = '',
  });

  @override
  Widget build(BuildContext context) {
    const lineColor = Color(0x66800020); // maroon @ 40%
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        children: [
          // ── Root node ──────────────────────────────────────────────────
          _RootNode(personName: personName),
          const _Spine(height: 22, color: lineColor),

          // ── Parents (Father · Mother) ──────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 26,
            child: CustomPaint(painter: _ForkPainter(lineColor)),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ParentCard(
                    role: 'Father',
                    icon: Icons.man_2_outlined,
                    name: family.fatherName,
                    occupation: family.fatherOccupation,
                    accent: AppColors.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ParentCard(
                    role: 'Mother',
                    icon: Icons.woman_2_outlined,
                    name: family.motherName,
                    occupation: family.motherOccupation,
                    accent: AppColors.primaryLight,
                  ),
                ),
              ],
            ),
          ),

          // ── Siblings ────────────────────────────────────────────────────
          if (family.brothersCount > 0 || family.sistersCount > 0) ...[
            const _Spine(height: 22, color: lineColor),
            _SiblingsCard(
              brothers: family.brothersCount,
              sisters: family.sistersCount,
            ),
          ],

          const SizedBox(height: 24),

          // ── Family Type · Status ────────────────────────────────────────
          Row(
            children: [
              if (family.familyType.trim().isNotEmpty)
                Expanded(
                  child: _AttributeCard(
                    icon: Icons.home_outlined,
                    label: 'Family Type',
                    value: _withSuffix(family.familyType, 'Family'),
                    accent: AppColors.primary,
                  ),
                ),
              if (family.familyType.trim().isNotEmpty &&
                  family.familyStatus.trim().isNotEmpty)
                const SizedBox(width: 12),
              if (family.familyStatus.trim().isNotEmpty)
                Expanded(
                  child: _AttributeCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Family Status',
                    value: family.familyStatus,
                    accent: AppColors.gold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Joint" → "Joint Family"; leaves "Nuclear Family" unchanged.
  static String _withSuffix(String value, String suffix) {
    final v = value.trim();
    return v.toLowerCase().endsWith(suffix.toLowerCase()) ? v : '$v $suffix';
  }
}

// ── Root "Family" pill ────────────────────────────────────────────────────────
class _RootNode extends StatelessWidget {
  final String personName;
  const _RootNode({required this.personName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.account_tree_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Family',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          if (personName.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              personName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Parent card (Father / Mother) ─────────────────────────────────────────────
class _ParentCard extends StatelessWidget {
  final String role;
  final IconData icon;
  final String name;
  final String occupation;
  final Color accent;

  const _ParentCard({
    required this.role,
    required this.icon,
    required this.name,
    required this.occupation,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: accent.withOpacity(0.12),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(height: 8),
          Text(role,
              style: TextStyle(
                  color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            name.trim().isEmpty ? 'Not specified' : name.trim(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: name.trim().isEmpty ? Colors.grey : AppColors.textPrimary,
            ),
          ),
          if (occupation.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              occupation.trim(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Siblings card ─────────────────────────────────────────────────────────────
class _SiblingsCard extends StatelessWidget {
  final int brothers;
  final int sisters;
  const _SiblingsCard({required this.brothers, required this.sisters});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _siblingStat(Icons.man_outlined, 'Brothers', brothers, AppColors.info),
          Container(width: 1, height: 38, color: AppColors.divider),
          _siblingStat(
              Icons.woman_outlined, 'Sisters', sisters, AppColors.primaryLight),
        ],
      ),
    );
  }

  Widget _siblingStat(IconData icon, String label, int count, Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accent, size: 24),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}

// ── Family type / status attribute card ───────────────────────────────────────
class _AttributeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _AttributeCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ── Vertical connector ────────────────────────────────────────────────────────
class _Spine extends StatelessWidget {
  final double height;
  final Color color;
  const _Spine({required this.height, required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 2.5, height: height, color: color);
}

/// Paints the "┬ splitting into two legs" connector between the root/parents
/// row. Legs land at 25% and 75% of the width — the centres of two equal-width
/// [Expanded] parent cards below.
class _ForkPainter extends CustomPainter {
  final Color color;
  _ForkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final midX = size.width / 2;
    final barY = size.height * 0.5;
    final leftX = size.width * 0.25;
    final rightX = size.width * 0.75;

    // Top stub (continues the spine from the root).
    canvas.drawLine(Offset(midX, 0), Offset(midX, barY), paint);
    // Horizontal bar.
    canvas.drawLine(Offset(leftX, barY), Offset(rightX, barY), paint);
    // Two legs down to each parent card.
    canvas.drawLine(Offset(leftX, barY), Offset(leftX, size.height), paint);
    canvas.drawLine(Offset(rightX, barY), Offset(rightX, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _ForkPainter old) => old.color != color;
}

// ── Empty / error state ───────────────────────────────────────────────────────
class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
