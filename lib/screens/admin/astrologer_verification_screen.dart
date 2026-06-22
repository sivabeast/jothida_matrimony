import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/astrologer_account_model.dart';
import '../../providers/admin_provider.dart';
import 'admin_certificates.dart';

enum _VFilter { all, pending, verified, rejected }

extension on _VFilter {
  String get label => switch (this) {
        _VFilter.all => 'All Requests',
        _VFilter.pending => 'Pending',
        _VFilter.verified => 'Verified',
        _VFilter.rejected => 'Rejected',
      };
}

VerificationStatus? _statusFor(_VFilter f) => switch (f) {
      _VFilter.all => null,
      _VFilter.pending => VerificationStatus.pending,
      _VFilter.verified => VerificationStatus.approved,
      _VFilter.rejected => VerificationStatus.rejected,
    };

(String, Color) _statusStyle(VerificationStatus s) => switch (s) {
      VerificationStatus.approved => ('VERIFIED', AppColors.success),
      VerificationStatus.rejected => ('REJECTED', AppColors.error),
      VerificationStatus.pending => ('PENDING', AppColors.warning),
    };

/// Dedicated Admin → Astrologer Verification queue, fully separate from the
/// Astrologers list. Filter by status, review each request (profile +
/// certificates), then Approve or Reject. Backed by the real-time
/// [allAstrologersProvider] stream, so an approval/rejection updates the list
/// and badges instantly.
class AstrologerVerificationScreen extends ConsumerStatefulWidget {
  const AstrologerVerificationScreen({super.key});

  @override
  ConsumerState<AstrologerVerificationScreen> createState() =>
      _AstrologerVerificationScreenState();
}

class _AstrologerVerificationScreenState
    extends ConsumerState<AstrologerVerificationScreen> {
  _VFilter _filter = _VFilter.pending;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAstrologersProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Astrologer Verification'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load verification requests.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(allAstrologersProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (all) {
          final counts = <VerificationStatus, int>{};
          for (final a in all) {
            counts[a.status] = (counts[a.status] ?? 0) + 1;
          }
          final want = _statusFor(_filter);
          final list = (want == null
              ? [...all]
              : all.where((a) => a.status == want).toList())
            ..sort((a, b) =>
                (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

          return Column(
            children: [
              _statusTabs(counts, all.length),
              Expanded(
                child: list.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: () async {
                          ref.invalidate(allAstrologersProvider);
                          await Future<void>.delayed(
                              const Duration(milliseconds: 250));
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _VerifyCard(astrologer: list[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusTabs(Map<VerificationStatus, int> counts, int total) {
    int countFor(_VFilter f) {
      final s = _statusFor(f);
      return s == null ? total : (counts[s] ?? 0);
    }

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final f in _VFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${f.label} (${countFor(f)})'),
                selected: _filter == f,
                showCheckmark: false,
                selectedColor: AppColors.primary.withOpacity(0.14),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: _filter == f ? AppColors.primary : Colors.black87,
                  fontWeight:
                      _filter == f ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
                side: BorderSide(
                    color:
                        _filter == f ? AppColors.primary : Colors.grey[300]!),
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 90),
          Icon(Icons.verified_user_outlined,
              size: 64, color: AppColors.primary.withOpacity(0.35)),
          const SizedBox(height: 14),
          const Center(
            child: Text('No requests in this category.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

// ── Verification request card ────────────────────────────────────────────────
class _VerifyCard extends ConsumerWidget {
  final AstrologerAccount astrologer;
  const _VerifyCard({required this.astrologer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = astrologer;
    final (label, color) = _statusStyle(a.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.gold.withOpacity(0.15),
                backgroundImage:
                    a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                child: a.photoUrl.isEmpty
                    ? const Icon(Icons.auto_awesome, color: AppColors.gold)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.fullName.isEmpty ? 'Astrologer' : a.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    _line(Icons.call_outlined, a.mobile.isEmpty ? '—' : a.mobile),
                    _line(Icons.mail_outline, a.email.isEmpty ? '—' : a.email),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _stat(Icons.work_history_outlined, '${a.experienceYears} yrs exp'),
              _stat(Icons.design_services_outlined, '${a.services.length} services'),
              _stat(Icons.workspace_premium_outlined,
                  '${a.certificates.length} certificates'),
              _stat(Icons.event_outlined,
                  a.createdAt == null ? 'Registered —' : 'Registered ${_fmtDate(a.createdAt!)}'),
            ],
          ),
          if (a.status == VerificationStatus.rejected &&
              a.rejectionReason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('Reason: ${a.rejectionReason}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[800])),
            ),
          ],
          const Divider(height: 22),
          // Review actions.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AdminAstrologerProfilePage(astrologer: a))),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Profile'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _CertsPage(astrologer: a))),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Certificates'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (a.status != VerificationStatus.approved)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approve(context, ref),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
              if (a.status != VerificationStatus.approved &&
                  a.status != VerificationStatus.rejected)
                const SizedBox(width: 8),
              if (a.status != VerificationStatus.rejected)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _reject(context, ref),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Reject'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(adminActionsProvider.notifier).approveAstrologer(astrologer.id);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not approve. Please try again.'
          : '${astrologer.fullName} verified. They were notified.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await _askReason(context);
    if (reason == null) return; // cancelled
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(adminActionsProvider.notifier)
        .rejectAstrologer(astrologer.id, reason: reason);
    final st = ref.read(adminActionsProvider);
    messenger.showSnackBar(SnackBar(
      content: Text(st.hasError
          ? 'Could not reject. Please try again.'
          : '${astrologer.fullName} rejected. They were notified to reapply.'),
      backgroundColor: st.hasError ? AppColors.error : null,
    ));
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Row(children: [
          Icon(icon, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
        ]),
      );

  Widget _stat(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      );
}

Future<String?> _askReason(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reject Verification'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Reason (shown to the astrologer)…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    ),
  );
}

// ── Certificates-only page (View Certificates) ───────────────────────────────
class _CertsPage extends StatelessWidget {
  final AstrologerAccount astrologer;
  const _CertsPage({required this.astrologer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(astrologer.fullName.isEmpty
            ? 'Certificates'
            : '${astrologer.fullName} · Certificates'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [CertificatesCard(certificates: astrologer.certificates)],
      ),
    );
  }
}

// ── Full astrologer profile (reused by management + verification) ─────────────
class AdminAstrologerProfilePage extends ConsumerWidget {
  final AstrologerAccount astrologer;
  const AdminAstrologerProfilePage({super.key, required this.astrologer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = astrologer;
    final (label, color) = _statusStyle(a.status);
    final services =
        a.services.isNotEmpty ? a.services.map((s) => s.name).toList() : a.expertise;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(a.fullName.isEmpty ? 'Astrologer' : a.fullName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.gold.withOpacity(0.15),
                  backgroundImage:
                      a.photoUrl.isNotEmpty ? NetworkImage(a.photoUrl) : null,
                  child: a.photoUrl.isEmpty
                      ? const Icon(Icons.auto_awesome,
                          size: 40, color: AppColors.gold)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(a.fullName.isEmpty ? 'Astrologer' : a.fullName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, size: 16, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text('${a.rating.toStringAsFixed(1)} · ${a.reviewCount} reviews',
                        style: TextStyle(color: Colors.grey[700])),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(label,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _section('Basic Details', Icons.info_outline, [
            _r('Experience', '${a.experienceYears} years'),
            _r('Languages',
                a.languages.isEmpty ? '—' : a.languages.join(', ')),
            _r('Qualification', a.qualification.isEmpty ? '—' : a.qualification),
            _r('Registered',
                a.createdAt == null ? '—' : _fmtDate(a.createdAt!)),
          ]),
          _wrapSection('Services', Icons.design_services_outlined,
              services.isEmpty ? const ['—'] : services),
          CertificatesCard(certificates: a.certificates),
          _section('Contact Details', Icons.call_outlined, [
            _r('Name', a.fullName),
            _r('Phone', a.mobile.isEmpty ? '—' : a.mobile),
            _r('WhatsApp', a.mobile.isEmpty ? '—' : a.mobile),
            _r('Email', a.email.isEmpty ? '—' : a.email),
            _r('Location',
                [a.district, a.city, a.state].where((s) => s.isNotEmpty).join(', ')),
          ]),
          _section('Ratings', Icons.reviews_outlined, [
            _r('Average Rating', a.rating.toStringAsFixed(1)),
            _r('Review Count', '${a.reviewCount}'),
          ]),
          const SizedBox(height: 8),
          // Verification actions (status-aware) — work from the profile too.
          if (a.status != VerificationStatus.approved)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .approveAstrologer(a.id);
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Astrologer verified and notified.')));
                  },
                  icon: const Icon(Icons.verified, size: 18),
                  label: const Text('Approve / Verify'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
          if (a.status != VerificationStatus.rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final reason = await _askReason(context);
                    if (reason == null || !context.mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    await ref
                        .read(adminActionsProvider.notifier)
                        .rejectAstrologer(a.id, reason: reason);
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Astrologer rejected and notified.')));
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      minimumSize: const Size.fromHeight(46)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── shared building blocks (file-local) ──────────────────────────────────────
Widget _section(String title, IconData icon, List<Widget> rows) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );

Widget _wrapSection(String title, IconData icon, List<String> chips) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in chips)
                Chip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  backgroundColor: AppColors.primary.withOpacity(0.06),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );

Widget _r(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13.5))),
        ],
      ),
    );

String _fmtDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
}
