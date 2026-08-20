import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_dialogs.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';
import '../../providers/astrology_team_stats_provider.dart';
import '../../widgets/common/data_states.dart';

/// Admin → Employee Commission Settings.
///
/// Employees are paid a COMMISSION per completed Horoscope Request (not a
/// salary). This is a single global rate stored on the astrology service config
/// (`analysisCommission`), editable here at any time.
///
/// Commission is credited ONLY when an assigned request is COMPLETED — never on
/// creation or assignment — and exactly once per request. The rate in force at
/// completion time is frozen onto that request, so editing the rate here changes
/// FUTURE completions only and never recalculates what past ones earned.
///
/// The page also lists, per employee: total assigned, completed, pending, the
/// current per-request rate and the total commission actually earned.
class EmployeeCommissionScreen extends ConsumerStatefulWidget {
  const EmployeeCommissionScreen({super.key});

  @override
  ConsumerState<EmployeeCommissionScreen> createState() =>
      _EmployeeCommissionScreenState();
}

class _EmployeeCommissionScreenState
    extends ConsumerState<EmployeeCommissionScreen> {
  final _ctrl = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _snack(String m, {bool error = false}) =>
      showAppSnack(context, m, error: error);

  Future<void> _save(AstrologyServiceConfig base) async {
    final amount = int.tryParse(_ctrl.text.trim());
    if (amount == null || amount < 0) {
      _snack('Enter a valid commission amount.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(astrologyConfigServiceProvider)
          .save(base.copyWith(analysisCommission: amount));
      if (mounted) _snack('Commission per report updated to ₹$amount.');
    } catch (e) {
      debugPrint('[EmployeeCommission] save failed: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission')) {
        _snack(
            'Save blocked by security rules. Deploy Firestore rules and '
            'try again.',
            error: true);
      } else {
        _snack('Could not save the commission. Please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(astrologyServiceConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Employee Commission'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const LoadingState(message: 'Loading commission…'),
        error: (_, __) => _form(AstrologyServiceConfig.defaults),
        data: (cfg) => _form(cfg),
      ),
    );
  }

  Widget _form(AstrologyServiceConfig cfg) {
    if (!_seeded) {
      _seeded = true;
      _ctrl.text = '${cfg.analysisCommission}';
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Commission Per Completed Report',
                  style: TextStyle(
                      fontSize: 15,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 6),
              Text(
                'Each employee earns this amount for every report they complete. '
                'Weekly commission = completed reports × this rate.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Commission per report (₹)',
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: AppColors.scaffoldBg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : () => _save(cfg),
            icon: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _CommissionBreakdown(),
      ],
    );
  }
}

/// Per-employee commission details (spec §12): assigned / completed / pending
/// counts, the current per-request rate and the commission actually earned.
///
/// "Total Earned" sums the amount frozen on each COMPLETED request, so it is
/// unaffected by a later change to the configured rate and can never
/// double-count a request whose completion was re-submitted.
class _CommissionBreakdown extends ConsumerWidget {
  const _CommissionBreakdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(astrologerStatsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COMMISSION BY EMPLOYEE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey[600])),
        const SizedBox(height: 10),
        if (stats.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'No employees yet. Add employees under Employee Management, then '
              'assign Horoscope Requests to them.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
          )
        else
          for (final s in stats)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.member.displayName.trim().isEmpty
                              ? s.member.email
                              : s.member.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('₹${s.totalCommission}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Total commission earned',
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                  const Divider(height: 18),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _metric('Assigned', '${s.totalAssigned}'),
                      _metric('Completed', '${s.completed}'),
                      _metric('Pending', '${s.pending + s.inProgress}'),
                      _metric('Per request', '₹${s.commissionPerReport}'),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      );
}
