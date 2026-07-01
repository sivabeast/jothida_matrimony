import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/service_providers.dart';
import '../../services/firebase/astrology_team_service.dart';
import 'astrologer_performance.dart';

/// Admin → Astrologer Accounts (spec §6).
///
/// The admin provisions astrologers by Gmail only — no passwords. An account is
/// "Awaiting sign-in" until the astrologer first logs in with Google; the
/// Active switch enables/disables them for login AND auto-assignment instantly.
class AstrologerAccountsScreen extends ConsumerWidget {
  const AstrologerAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _addDialog(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add Employee'),
      ),
      // Performance dashboard — photo, name, Gmail, status + live workload &
      // earnings per astrologer, with View Details (spec §4).
      body: const AstrologerPerformanceList(bottomPadding: 90),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref) async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Employee'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter the full name' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'employee@gmail.com',
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Enter an email address';
                  if (!s.contains('@') || !s.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: mobileCtrl,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Mobile Number'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (added == true) {
      try {
        await ref.read(astrologyTeamServiceProvider).addMember(
              email: emailCtrl.text,
              displayName: nameCtrl.text,
              mobile: mobileCtrl.text,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Employee added. They can now sign in with '
                  'Google using that email to open the Employee Portal.'),
              backgroundColor: Colors.green));
        }
      } on AstrologerExistsException {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('This email is already registered as an employee.'),
              backgroundColor: AppColors.error));
        }
      } catch (e) {
        // Surface the real reason (e.g. a permission error) so it is actionable
        // instead of a generic "try again".
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not add employee: $e'),
              backgroundColor: AppColors.error));
        }
      }
    }
  }
}
