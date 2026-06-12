import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/dev_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/profile_model.dart';
import '../../models/report_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/service_providers.dart';

/// Report a profile. Registered at `/report/:id` (the reported profile id).
/// Reached from the profile view screen's "Report" action.
class ReportProfileScreen extends ConsumerStatefulWidget {
  final String profileId;
  const ReportProfileScreen({super.key, required this.profileId});

  @override
  ConsumerState<ReportProfileScreen> createState() =>
      _ReportProfileScreenState();
}

class _ReportProfileScreenState extends ConsumerState<ReportProfileScreen> {
  String? _reason;
  final TextEditingController _descCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(ProfileModel target) async {
    if (_reason == null) {
      _toast('Please select a reason for reporting.');
      return;
    }
    debugPrint('[ReportProfile] submitting report for ${target.id} '
        '(reason=$_reason)');
    setState(() => _submitting = true);

    final me = ref.read(currentUserProvider).valueOrNull;
    final myProfile = ref.read(myProfileProvider).valueOrNull;
    final report = ReportModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      reporterUserId: me?.uid ?? myProfile?.userId ?? 'unknown',
      reporterName: me?.displayName ?? myProfile?.name ?? 'Anonymous',
      reportedUserId: target.userId,
      reportedProfileId: target.id,
      reportedName: target.name,
      reason: _reason!,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      alertLevel: 'normal',
      createdAt: DateTime.now(),
    );

    try {
      // Demo mode has no Firebase backend — acknowledge without writing.
      if (!kBypassAuth) {
        await ref.read(firestoreServiceProvider).submitReport(report);
      }
      if (mounted) {
        _toast('Report submitted. Our team will review it.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[ReportProfile] submit error: $e');
      if (mounted) _toast('Could not submit report. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[ReportProfileScreen] build — route /report/${widget.profileId}');
    final targetAsync = ref.watch(profileByIdProvider(widget.profileId));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Report Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: targetAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Could not load profile: $e')),
        data: (target) {
          if (target == null) {
            return const Center(child: Text('Profile not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.error.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: AppColors.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You are reporting ${target.name}. False reports may '
                        'affect your account.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Why are you reporting this profile?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              ...AppConstants.reportReasons.map((r) => RadioListTile<String>(
                    value: r,
                    groupValue: _reason,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r),
                    onChanged: (v) => setState(() => _reason = v),
                  )),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Additional details (optional)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : () => _submit(target),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'Submitting...' : 'Submit Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
