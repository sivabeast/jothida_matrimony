import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/astrology_service_config.dart';
import '../../providers/astrology_config_provider.dart';

/// Admin → Employee Commission Settings.
///
/// Employees are paid a COMMISSION per completed Horoscope Compatibility Report
/// (not a salary). This is a single global rate stored on the astrology service
/// config (`analysisCommission`). Editable here at any time; changes apply to
/// all future commission calculations across the admin + employee views.
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

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save(AstrologyServiceConfig base) async {
    final amount = int.tryParse(_ctrl.text.trim());
    if (amount == null || amount < 0) {
      _snack('Enter a valid commission amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(astrologyConfigServiceProvider)
          .save(base.copyWith(analysisCommission: amount));
      if (mounted) _snack('✅ Commission per report updated to ₹$amount.');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission')) {
        _snack('Save blocked by security rules. Deploy Firestore rules and '
            'try again.');
      } else {
        _snack('Could not save: $e');
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
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
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
      ],
    );
  }
}
