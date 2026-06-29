import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/appointment_status.dart';
import '../../core/utils/slot_generator.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/network_photo.dart';

enum _ApptFilter { all, today, upcoming, confirmed, pending, completed, cancelled }

extension _ApptFilterX on _ApptFilter {
  String get label => switch (this) {
        _ApptFilter.all => 'All',
        _ApptFilter.today => 'Today',
        _ApptFilter.upcoming => 'Upcoming',
        _ApptFilter.confirmed => 'Confirmed',
        _ApptFilter.pending => 'Pending',
        _ApptFilter.completed => 'Completed',
        _ApptFilter.cancelled => 'Cancelled',
      };
}

/// Admin → Appointment Management. A dedicated page (separate from Astrology
/// Management) listing EVERY appointment booking with full user details, live
/// status, search + filters and per-booking actions. Fully database-driven via
/// [allAppointmentsProvider]; status changes sync to the user instantly.
class AdminAppointmentsScreen extends ConsumerStatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  ConsumerState<AdminAppointmentsScreen> createState() =>
      _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState
    extends ConsumerState<AdminAppointmentsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _ApptFilter _filter = _ApptFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesFilter(AstrologerRequestModel r) {
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final visit = r.visitDate == null
        ? null
        : DateTime(r.visitDate!.year, r.visitDate!.month, r.visitDate!.day);
    switch (_filter) {
      case _ApptFilter.all:
        return true;
      case _ApptFilter.today:
        return visit != null && visit == t0;
      case _ApptFilter.upcoming:
        return visit != null &&
            !visit.isBefore(t0) &&
            (r.status == AstrologerRequestStatus.pending ||
                r.status == AstrologerRequestStatus.accepted);
      case _ApptFilter.confirmed:
        return r.status == AstrologerRequestStatus.accepted;
      case _ApptFilter.pending:
        return r.status == AstrologerRequestStatus.pending;
      case _ApptFilter.completed:
        return r.status == AstrologerRequestStatus.completed;
      case _ApptFilter.cancelled:
        return r.status == AstrologerRequestStatus.rejected;
    }
  }

  bool _matchesQuery(AstrologerRequestModel r) {
    if (_query.trim().isEmpty) return true;
    final q = _query.trim().toLowerCase();
    return r.userName.toLowerCase().contains(q) ||
        r.userPhone.toLowerCase().contains(q) ||
        r.id.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allAppointmentsProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Appointment Management'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _searchBar(),
          _filterChips(),
          Expanded(
            child: async.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, __) => _message('Could not load appointments.\n$e'),
              data: (all) {
                final list = all
                    .where(_matchesFilter)
                    .where(_matchesQuery)
                    .toList();
                if (list.isEmpty) {
                  return _message('No appointments match this view.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _AppointmentAdminCard(appt: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search by name, mobile or booking ID',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  Widget _filterChips() => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final f in _ApptFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  labelStyle: TextStyle(
                    color: _filter == f ? AppColors.primary : Colors.black87,
                    fontWeight:
                        _filter == f ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 12.5,
                  ),
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ],
        ),
      );

  Widget _message(String m) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(m,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13.5)),
        ),
      );
}

class _AppointmentAdminCard extends ConsumerWidget {
  final AstrologerRequestModel appt;
  const _AppointmentAdminCard({required this.appt});

  void _snack(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _setStatus(BuildContext context, WidgetRef ref,
      AstrologerRequestStatus status) async {
    try {
      await ref
          .read(appointmentControllerProvider.notifier)
          .setStatus(appt, status);
      if (context.mounted) {
        _snack(context, 'Appointment ${appointmentStatusLabel(status)}.');
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Action failed. Please try again.');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete appointment?'),
        content: const Text(
            'This permanently removes the booking and frees its slot.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appointmentControllerProvider.notifier).delete(appt);
      if (context.mounted) _snack(context, 'Appointment deleted.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Delete failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve mobile + photo: prefer the denormalised values; fall back to the
    // live profile only when missing (older records).
    final profile = (appt.userPhone.isEmpty || appt.userPhotoUrl.isEmpty)
        ? ref.watch(profileByUserIdProvider(appt.userId)).valueOrNull
        : null;
    final phone = appt.userPhone.isNotEmpty
        ? appt.userPhone
        : (profile?.contact.mobileNumber ?? '');
    final photo =
        appt.userPhotoUrl.isNotEmpty ? appt.userPhotoUrl : (profile?.profilePhotoUrl ?? '');
    final color = appointmentStatusColor(appt.status);
    final date = appt.visitDate == null
        ? '—'
        : DateFormat('EEE, d MMM yyyy').format(appt.visitDate!);
    final time =
        appt.slotStartMinutes == null ? '—' : formatMinutes(appt.slotStartMinutes!);
    final created = DateFormat('d MMM yyyy, h:mm a').format(appt.createdAt);

    return Container(
      padding: const EdgeInsets.all(14),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: NetworkPhoto(url: photo, width: 48, height: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('ID: ${appt.userId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    if (phone.isNotEmpty)
                      Text('📞 $phone',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(appointmentStatusLabel(appt.status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(child: _info(Icons.event_outlined, 'Date', date)),
              Expanded(child: _info(Icons.schedule_outlined, 'Time', time)),
            ],
          ),
          const SizedBox(height: 8),
          _info(Icons.confirmation_number_outlined, 'Booking ID', appt.id),
          const SizedBox(height: 6),
          _info(Icons.history_toggle_off_outlined, 'Created', created),
          const SizedBox(height: 10),
          _actions(context, ref),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _actions(BuildContext context, WidgetRef ref) {
    final s = appt.status;
    final chips = <Widget>[
      if (s != AstrologerRequestStatus.accepted)
        _actionBtn(context, 'Confirm', Icons.check_circle_outline,
            AppColors.success, () => _setStatus(context, ref, AstrologerRequestStatus.accepted)),
      if (s != AstrologerRequestStatus.pending)
        _actionBtn(context, 'Pending', Icons.hourglass_top_outlined,
            AppColors.warning, () => _setStatus(context, ref, AstrologerRequestStatus.pending)),
      if (s != AstrologerRequestStatus.completed)
        _actionBtn(context, 'Complete', Icons.verified_outlined, AppColors.info,
            () => _setStatus(context, ref, AstrologerRequestStatus.completed)),
      if (s != AstrologerRequestStatus.rejected)
        _actionBtn(context, 'Cancel', Icons.cancel_outlined, AppColors.error,
            () => _setStatus(context, ref, AstrologerRequestStatus.rejected)),
      _actionBtn(context, 'Delete', Icons.delete_outline, Colors.grey.shade700,
          () => _delete(context, ref)),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _actionBtn(BuildContext context, String label, IconData icon,
          Color color, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}
