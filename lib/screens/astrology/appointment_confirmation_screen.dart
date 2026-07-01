import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrologer_request_model.dart';
import '../../providers/chat_provider.dart';

/// Appointment confirmation (spec §11). Shown after a successful payment, it
/// displays the Booking ID, appointment date & time, office address and contact
/// number, and offers a shortcut to the auto-created Astrology Analysis Chat and
/// the Reports page.
class AppointmentConfirmationScreen extends ConsumerWidget {
  final String bookingId;

  /// `{date, session, address, contact, groom, bride, internalUid, expertName,
  /// expertPhoto}` passed from the booking screen.
  final Map<String, dynamic>? extra;

  const AppointmentConfirmationScreen({
    super.key,
    required this.bookingId,
    this.extra,
  });

  DateTime? get _date => extra?['date'] as DateTime?;
  String get _session => (extra?['session'] as String?) ?? '';
  String get _address => (extra?['address'] as String?) ?? '';
  String get _contact => (extra?['contact'] as String?) ?? '';
  String get _internalUid => (extra?['internalUid'] as String?) ?? '';
  String get _expertName => (extra?['expertName'] as String?) ?? 'Astrology Service';
  String get _expertPhoto => (extra?['expertPhoto'] as String?) ?? '';

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_internalUid.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Your analysis chat will open once our team begins your report.')));
      return;
    }
    try {
      final id = await ref.read(chatControllerProvider).openChatWith(
            otherUid: _internalUid,
            otherName: _expertName,
            otherPhoto: _expertPhoto,
          );
      if (!context.mounted) return;
      context.push('/chat/$id', extra: {
        'name': _expertName,
        'photo': _expertPhoto,
        'isAstrologer': true,
      });
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not open chat. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Appointment Confirmed'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      color: AppColors.success, size: 56),
                ),
                const SizedBox(height: 14),
                const Text('Your appointment is booked!',
                    style: TextStyle(
                        fontSize: 18,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Please visit our office at the scheduled date and time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                _row(Icons.confirmation_number_outlined, 'Booking ID',
                    bookingId),
                const Divider(height: 20),
                _row(
                    Icons.event_outlined,
                    'Appointment Date',
                    _date == null
                        ? '—'
                        : DateFormat('EEEE, d MMM yyyy').format(_date!)),
                const Divider(height: 20),
                _row(Icons.schedule_outlined, 'Session',
                    _session.isEmpty ? '—' : AppointmentSession.label(_session)),
                const Divider(height: 20),
                _row(Icons.location_on_outlined, 'Office Address',
                    _address.isEmpty ? '—' : _address),
                const Divider(height: 20),
                _row(Icons.call_outlined, 'Contact Number',
                    _contact.isEmpty ? '—' : _contact),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openChat(context, ref),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('Open Analysis Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/my-analysis'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View My Reports'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                minimumSize: const Size.fromHeight(50),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Back to Home'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}
